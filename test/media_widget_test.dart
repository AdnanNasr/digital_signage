import 'dart:async';
import 'dart:convert';

import 'package:digital_signage/features/media/media_page.dart';
import 'package:digital_signage/main.dart';
import 'package:digital_signage/models/media_file.dart';
import 'package:digital_signage/providers/dashboard_provider.dart';
import 'package:digital_signage/services/signage_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'widget_test.dart' show FakeServer, login, closeApp;

class MediaServer extends FakeServer {
  final files = <String>['Grüße & Angebote.mp4'];
  final deleted = <String>[];
  bool protect = false;
  bool failList = false;

  @override
  Future<http.Response> handle(http.Request request) async {
    if (request.url.path.startsWith('/api/media')) {
      if (unauthorized) return http.Response('{}', 401);
      if (request.method == 'DELETE') {
        if (protect) {
          return http.Response(
            '{"detail":"Bitte zuerst die Wiedergabe stoppen."}',
            409,
          );
        }
        final id = request.url.pathSegments.last;
        expect(request.url.queryParameters['confirm'], 'true');
        files.remove(id);
        deleted.add(id);
        return http.Response('', 204);
      }
      if (failList) throw http.ClientException('offline');
      return http.Response(
        jsonEncode(
          files
              .map(
                (name) => {
                  'id': name,
                  'name': name,
                  'type': 'video',
                  'size_bytes': 1024 * 1024,
                },
              )
              .toList(),
        ),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return super.handle(request);
  }
}

class FakeUpload implements VideoUpload {
  FakeUpload(this.server);
  final MediaServer server;
  final completion = Completer<void>();
  void Function(double)? progress;
  bool cancelled = false;
  Uri? url;
  String? token;
  @override
  String name = 'Neues Video.mp4';
  @override
  int size = 50;
  @override
  Future<void> send(
    Uri url,
    String token,
    void Function(double) onProgress,
  ) async {
    this.url = url;
    this.token = token;
    progress = onProgress;
    onProgress(0.5);
    await completion.future;
    server.files.add(name);
  }

  @override
  void cancel() {
    cancelled = true;
    if (!completion.isCompleted) {
      completion.completeError(const ApiException('Upload abgebrochen.'));
    }
  }
}

Future<void> openMedia(
  WidgetTester tester,
  MediaServer server, {
  FakeUpload? upload,
  double width = 1000,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        httpClientProvider.overrideWithValue(MockClient(server.handle)),
        videoPickerProvider.overrideWithValue(() async => upload),
      ],
      child: const SignageApp(),
    ),
  );
  await login(tester);
  await tester.tap(find.text('Medien'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('expired session returns to login from media requests', (
    tester,
  ) async {
    final server = MediaServer();
    await openMedia(tester, server);
    server.unauthorized = true;
    await tester.tap(find.text('Dateien aktualisieren'));
    await tester.pumpAndSettle();
    expect(find.text('Verbinden'), findsOneWidget);
    expect(find.textContaining('Passwort ist ungültig'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('lists German filenames and only deletes after confirmation', (
    tester,
  ) async {
    final server = MediaServer();
    await openMedia(tester, server);
    expect(find.text('Grüße & Angebote.mp4'), findsOneWidget);
    expect(find.text('1,0 MiB'), findsOneWidget);
    await tester.tap(find.byTooltip('Grüße & Angebote.mp4 löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(server.deleted, isEmpty);
    await tester.tap(find.byTooltip('Grüße & Angebote.mp4 löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    expect(server.deleted, ['Grüße & Angebote.mp4']);
    expect(find.text('Video erfolgreich gelöscht.'), findsOneWidget);
    expect(find.textContaining('Noch keine Videos'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets('protected file stays listed with useful server feedback', (
    tester,
  ) async {
    final server = MediaServer()..protect = true;
    await openMedia(tester, server);
    await tester.tap(find.byTooltip('Grüße & Angebote.mp4 löschen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    expect(find.text('Bitte zuerst die Wiedergabe stoppen.'), findsOneWidget);
    expect(find.text('Grüße & Angebote.mp4'), findsOneWidget);
    await closeApp(tester);
  });

  testWidgets(
    'upload shows progress and validation and survives switching tabs',
    (tester) async {
      final server = MediaServer();
      final upload = FakeUpload(server);
      await openMedia(tester, server, upload: upload);
      await tester.tap(find.text('Video hochladen'));
      await tester.pump();
      await tester.pump();
      expect(find.text('Wird hochgeladen … 50 %'), findsOneWidget);
      expect(upload.url!.queryParameters['filename'], upload.name);
      expect(upload.token, 'DemoPass123');
      upload.progress!(1);
      await tester.pump();
      expect(find.text('Video wird geprüft …'), findsOneWidget);
      await tester.tap(find.text('Übersicht'));
      await tester.pump();
      expect(upload.cancelled, isFalse);
      upload.completion.complete();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Medien'));
      await tester.pumpAndSettle();
      expect(find.text('Neues Video.mp4'), findsOneWidget);
      expect(find.text('Video erfolgreich hochgeladen.'), findsOneWidget);
      await closeApp(tester);
    },
  );

  testWidgets('failed upload reports error and allows retry', (tester) async {
    final server = MediaServer();
    final upload = FakeUpload(server);
    await openMedia(tester, server, upload: upload);
    await tester.tap(find.text('Video hochladen'));
    await tester.pump();
    await tester.pump();
    upload.completion.completeError(
      const ApiException('Die Datei überschreitet die erlaubte Größe.', 413),
    );
    await tester.pumpAndSettle();
    expect(
      find.text('Die Datei überschreitet die erlaubte Größe.'),
      findsOneWidget,
    );
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, 'Video hochladen'),
          )
          .onPressed,
      isNotNull,
    );
    expect(server.files, hasLength(1));
    await closeApp(tester);
  });

  testWidgets('logging out aborts upload and clears session', (tester) async {
    final server = MediaServer();
    final upload = FakeUpload(server);
    await openMedia(tester, server, upload: upload);
    await tester.tap(find.text('Video hochladen'));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byTooltip('Abmelden'));
    await tester.pumpAndSettle();
    expect(upload.cancelled, isTrue);
    expect(find.text('Verbinden'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await closeApp(tester);
  });

  testWidgets(
    'small screen supports listing and confirmation without overflow',
    (tester) async {
      final server = MediaServer();
      await openMedia(tester, server, width: 320);
      await tester.scrollUntilVisible(
        find.byTooltip('Grüße & Angebote.mp4 löschen'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.byTooltip('Grüße & Angebote.mp4 löschen'));
      await tester.pumpAndSettle();
      expect(find.text('Video löschen?'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('Abbrechen'));
      await tester.pumpAndSettle();
      await closeApp(tester);
    },
  );

  testWidgets('list failure can be retried', (tester) async {
    final server = MediaServer()..failList = true;
    await openMedia(tester, server);
    expect(find.textContaining('Keine Verbindung zum Server'), findsOneWidget);
    server.failList = false;
    await tester.tap(find.text('Dateien aktualisieren'));
    await tester.pumpAndSettle();
    expect(find.text('Grüße & Angebote.mp4'), findsOneWidget);
    await closeApp(tester);
  });
}
