import 'dart:convert';

import 'package:digital_signage/main.dart';
import 'package:digital_signage/providers/dashboard_provider.dart';
import 'package:digital_signage/features/display/display_selectors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'media_widget_test.dart' show MediaServer;
import 'widget_test.dart' show login, closeApp;

class DisplayServer extends MediaServer {
  int rotation = 180;
  String fit = 'contain';
  bool available = true;
  bool fail = false;
  final changes = <Map<String, dynamic>>[];
  @override
  Future<http.Response> handle(http.Request request) async {
    if (!request.url.path.startsWith('/api/display')) {
      return super.handle(request);
    }
    if (unauthorized) return http.Response('{}', 401);
    if (request.method != 'GET') {
      if (fail) {
        return json({
          'detail': 'Die Einstellungen konnten nicht übernommen werden.',
        }, 503);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      changes.add(body);
      if (request.url.path.endsWith('/reset')) {
        rotation = 0;
        fit = 'contain';
      } else {
        rotation = body['rotation'] as int? ?? rotation;
        fit = body['fit_mode'] as String? ?? fit;
      }
    }
    return json({
      'output': available ? 'DP-2' : null,
      'rotation': available ? rotation : null,
      'fit_mode': fit,
      'session': 'wayland',
      'available': available,
      'resolution': available ? {'width': 1920, 'height': 1080} : null,
      'error': available ? null : 'Der Bildschirm ist nicht erreichbar.',
      'outputs': [
        if (available)
          {
            'name': 'DP-2',
            'rotation': rotation,
            'rotations': [0, 90, 180, 270],
            'resolution': {'width': 1920, 'height': 1080},
          },
      ],
    });
  }

  http.Response json(Object value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

Future<void> openDisplay(
  WidgetTester tester,
  DisplayServer server, {
  double width = 1100,
}) async {
  tester.view.physicalSize = Size(width, 950);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        httpClientProvider.overrideWithValue(MockClient(server.handle)),
      ],
      child: const SignageApp(),
    ),
  );
  await login(tester);
  await tester.tap(find.byKey(const Key('settings-tab')).first);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('actual orientation, preview, combined application and reset', (
    tester,
  ) async {
    final server = DisplayServer();
    await openDisplay(tester, server);
    expect(find.text('DP-2'), findsOneWidget);
    expect(
      tester
          .widget<DisplayOrientationSelector>(
            find.byType(DisplayOrientationSelector),
          )
          .value,
      180,
    );
    await tester.tap(find.byType(DisplayOrientationSelector));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Hochformat – 90°').last);
    await tester.pumpAndSettle();
    expect(server.changes, isEmpty);
    expect(
      tester
          .widget<DisplayOrientationPreview>(
            find.byType(DisplayOrientationPreview),
          )
          .rotation,
      90,
    );
    await tester.ensureVisible(find.byType(DisplayFitModeSelector));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(DisplayFitModeSelector));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bildschirm ausfüllen').last);
    await tester.pumpAndSettle();
    final apply = find.text('Einstellungen übernehmen');
    await tester.ensureVisible(apply);
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(server.changes.single, {
      'rotation': 90,
      'output': 'DP-2',
      'fit_mode': 'cover',
    });
    final reset = find.text('Auf Standard zurücksetzen');
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Zurücksetzen'));
    await tester.pumpAndSettle();
    expect(server.rotation, 0);
    expect(server.fit, 'contain');
    await closeApp(tester);
  });
  testWidgets(
    'unreachable output still permits fit settings and failures reload actual values',
    (tester) async {
      final server = DisplayServer()..available = false;
      await openDisplay(tester, server);
      expect(find.text('Der Bildschirm ist nicht erreichbar.'), findsWidgets);
      expect(
        tester
            .widget<DisplayOrientationSelector>(
              find.byType(DisplayOrientationSelector),
            )
            .onChanged,
        isNull,
      );
      server.fail = true;
      final apply = find.text('Einstellungen übernehmen');
      await tester.ensureVisible(apply);
      await tester.pumpAndSettle();
      await tester.tap(apply);
      await tester.pumpAndSettle();
      expect(
        find.text('Die Einstellungen konnten nicht übernommen werden.'),
        findsOneWidget,
      );
      expect(server.changes, isEmpty);
      await closeApp(tester);
    },
  );
  testWidgets('display form fits a narrow screen', (tester) async {
    final server = DisplayServer();
    await openDisplay(tester, server, width: 320);
    final apply = find.text('Einstellungen übernehmen');
    await tester.ensureVisible(apply);
    await tester.pumpAndSettle();
    await tester.tap(apply);
    await tester.pumpAndSettle();
    expect(server.changes, isNotEmpty);
    expect(tester.takeException(), isNull);
    await closeApp(tester);
  });
}
