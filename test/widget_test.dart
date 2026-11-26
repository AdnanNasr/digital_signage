import 'dart:convert';

import 'package:digital_signage/main.dart';
import 'package:digital_signage/providers/dashboard_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

class FakeServer {
  String state = 'stopped';
  bool offline = false;
  bool unauthorized = false;
  int videos = 2;
  final commands = <String>[];

  Future<http.Response> handle(http.Request request) async {
    if (offline) throw http.ClientException('offline');
    if (unauthorized) return http.Response('{}', 401);
    if (request.method == 'POST') {
      final command = request.url.path.split('/').last;
      commands.add(command);
      state = switch (command) {
        'start' || 'resume' || 'restart' => 'playing',
        'pause' => 'paused',
        'stop' => 'stopped',
        _ => state,
      };
    }
    return http.Response(
      jsonEncode({
        'state': state,
        'reachable': state != 'stopped',
        'video_count': videos,
        'current_file': state == 'stopped'
            ? null
            : 'Werbung für unser Geschäft.mp4',
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  }
}

Future<void> openApp(
  WidgetTester tester,
  FakeServer server, {
  double width = 1200,
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
}

Future<void> login(WidgetTester tester) async {
  await tester.enterText(find.byKey(const Key('access-token')), 'DemoPass123');
  await tester.ensureVisible(find.text('Verbinden'));
  await tester.tap(find.text('Verbinden'));
  await tester.pumpAndSettle();
}

Future<void> tapControl(WidgetTester tester, String label) async {
  if (find.text(label).evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      find.text(label),
      250,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(find.text(label));
  await tester.tap(find.text(label));
  await tester.pumpAndSettle();
}

Future<void> closeApp(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

void main() {
  testWidgets('connects and sends all playback commands', (tester) async {
    final server = FakeServer();
    await openApp(tester, server);
    await login(tester);
    expect(find.text('Übersicht'), findsOneWidget);
    expect(find.text('Verbunden'), findsOneWidget);
    expect(find.text('Gestoppt'), findsOneWidget);
    await tapControl(tester, 'Wiedergabe starten');
    expect(find.text('Wird wiedergegeben'), findsOneWidget);
    expect(find.text('Werbung für unser Geschäft.mp4'), findsOneWidget);
    await tapControl(tester, 'Pause');
    expect(find.text('Pausiert'), findsOneWidget);
    await tapControl(tester, 'Fortsetzen');
    await tapControl(tester, 'Nächste Datei');
    await tapControl(tester, 'Vorherige Datei');
    await tapControl(tester, 'Neu starten');
    await tapControl(tester, 'Wiedergabe stoppen');
    expect(server.commands, [
      'start',
      'pause',
      'resume',
      'next',
      'previous',
      'restart',
      'stop',
    ]);
    await tester.tap(find.byTooltip('Abmelden'));
    await tester.pumpAndSettle();
    expect(find.text('Verbinden'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const Key('access-token')))
          .controller!
          .text,
      isEmpty,
    );
    await closeApp(tester);
  });

  testWidgets('polling detects disconnection and recovers without stale data', (
    tester,
  ) async {
    final server = FakeServer()..state = 'playing';
    await openApp(tester, server);
    await login(tester);
    server.offline = true;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Unterbrochen'), findsOneWidget);
    expect(find.text('Werbung für unser Geschäft.mp4'), findsNothing);
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Pause'))
          .onPressed,
      isNull,
    );
    server.offline = false;
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('Verbunden'), findsOneWidget);
    expect(find.text('Werbung für unser Geschäft.mp4'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('invalid token stays on connection form with German feedback', (
    tester,
  ) async {
    final server = FakeServer()..unauthorized = true;
    await openApp(tester, server);
    await login(tester);
    expect(find.textContaining('Passwort ist ungültig'), findsOneWidget);
    expect(find.text('Übersicht'), findsNothing);
    await closeApp(tester);
  });

  testWidgets(
    'small screen supports connection and playback without overflow',
    (tester) async {
      final server = FakeServer();
      await openApp(tester, server, width: 320);
      await login(tester);
      await tapControl(tester, 'Wiedergabe starten');
      await tapControl(tester, 'Pause');
      expect(server.commands, ['start', 'pause']);
      expect(tester.takeException(), isNull);
      await closeApp(tester);
    },
  );

  testWidgets('empty library disables start and restart', (tester) async {
    final server = FakeServer()..videos = 0;
    await openApp(tester, server);
    await login(tester);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Wiedergabe starten'),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Neu starten'),
          )
          .onPressed,
      isNull,
    );
    await closeApp(tester);
  });
}
