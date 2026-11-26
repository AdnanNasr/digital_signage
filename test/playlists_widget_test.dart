import 'dart:convert';

import 'package:digital_signage/main.dart';
import 'package:digital_signage/providers/dashboard_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'media_widget_test.dart' show MediaServer;
import 'widget_test.dart' show login, closeApp;

class PlaylistServer extends MediaServer {
  final lists = <Map<String, dynamic>>[];
  String? selected;
  String? playing;
  final started = <String>[];
  int _nextId = 1;

  void seed(String name, {List<String>? items}) {
    lists.add({
      'id': 'list-${_nextId++}',
      'name': name,
      'items': items ?? ['Angebot.png'],
      'image_duration': 10,
      'loop': true,
      'revision': 1,
    });
  }

  http.Response json(Object? value, [int status = 200]) => http.Response(
    jsonEncode(value),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  Map<String, dynamic> get collection => {
    'selected_id': selected,
    'playlists': lists,
  };

  @override
  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (path.startsWith('/api/playlists')) {
      if (unauthorized) return json({}, 401);
      if (request.method == 'GET') return json(collection);
      if (path.endsWith('/selected')) {
        selected =
            (jsonDecode(request.body) as Map<String, dynamic>)['id'] as String?;
        return json(collection);
      }
      if (path.endsWith('/start')) {
        playing = request.url.pathSegments[2];
        selected = playing;
        started.add(playing!);
        state = 'playing';
        return json({});
      }
      if (request.method == 'DELETE') {
        lists.removeWhere(
          (item) => item['id'] == request.url.pathSegments.last,
        );
        return http.Response('', 204);
      }
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      if (request.method == 'POST') {
        final item = {...body, 'id': 'list-${_nextId++}', 'revision': 1};
        lists.add(item);
        return json(item, 201);
      }
      final item = lists.firstWhere(
        (item) => item['id'] == request.url.pathSegments.last,
      );
      expect(body['revision'], item['revision']);
      item.addAll({...body, 'revision': (item['revision'] as int) + 1});
      return json(item);
    }
    if (path == '/api/media') {
      return json([
        {
          'id': 'Angebot.png',
          'name': 'Angebot.png',
          'type': 'image',
          'size_bytes': 100,
        },
        {
          'id': 'Werbung.mp4',
          'name': 'Werbung.mp4',
          'type': 'video',
          'size_bytes': 200,
        },
      ]);
    }
    final response = await super.handle(request);
    if (path.startsWith('/api/player') && response.statusCode == 200) {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final active = state == 'playing' || state == 'paused';
      data['image_count'] = 1;
      data['current_playlist_id'] = active ? playing : null;
      data['current_playlist_name'] = active && playing != null
          ? lists.firstWhere((item) => item['id'] == playing)['name']
          : null;
      return json(data);
    }
    return response;
  }
}

Future<void> openLists(
  WidgetTester tester,
  PlaylistServer server, {
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
  await tester.tap(find.byKey(const Key('playlists-tab')).first);
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pump();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'creates a mixed playlist with image duration and repeat setting',
    (tester) async {
      final server = PlaylistServer();
      await openLists(tester, server);
      await tester.tap(find.text('Neue Liste'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('playlist-name')),
        'Schaufenster',
      );
      await tester.enterText(find.byKey(const Key('image-duration')), '7');
      await tapVisible(tester, find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.text('Angebot.png').last);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.byType(DropdownButtonFormField<String>));
      await tester.tap(find.text('Werbung.mp4').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Speichern'));
      await tester.pumpAndSettle();
      expect(server.lists.single['items'], ['Angebot.png', 'Werbung.mp4']);
      expect(server.lists.single['image_duration'], 7);
      expect(find.text('Wiedergabeliste gespeichert.'), findsOneWidget);
      await closeApp(tester);
    },
  );

  testWidgets('edits order and removes entries without deleting media', (
    tester,
  ) async {
    final server = PlaylistServer()
      ..seed('Morgens', items: ['Angebot.png', 'Werbung.mp4']);
    await openLists(tester, server);
    await tapVisible(tester, find.byKey(const ValueKey('edit-list-1')));
    await tapVisible(tester, find.byTooltip('Angebot.png nach unten'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(server.lists.single['items'], ['Werbung.mp4', 'Angebot.png']);
    await tapVisible(tester, find.byKey(const ValueKey('edit-list-1')));
    await tapVisible(tester, find.byTooltip('Angebot.png aus Liste entfernen'));
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(server.lists.single['items'], ['Werbung.mp4']);
    expect(server.deleted, isEmpty);
    await closeApp(tester);
  });

  testWidgets(
    'selects a default without interrupting playback then starts chosen list',
    (tester) async {
      final server = PlaylistServer()
        ..seed('Morgens')
        ..seed('Abends');
      await openLists(tester, server);
      await tester.tap(find.byKey(const Key('selected-playlist')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Abends').last);
      await tester.pumpAndSettle();
      expect(server.selected, 'list-2');
      expect(server.started, isEmpty);
      await tapVisible(tester, find.byKey(const ValueKey('play-list-2')));
      expect(server.started, ['list-2']);
      expect(find.text('Läuft'), findsOneWidget);
      await tester.tap(find.text('Übersicht'));
      await tester.pumpAndSettle();
      expect(find.text('Wiedergabeliste: Abends'), findsOneWidget);
      await closeApp(tester);
    },
  );

  testWidgets('empty lists cannot play and delete requires confirmation', (
    tester,
  ) async {
    final server = PlaylistServer()..seed('Leer', items: []);
    await openLists(tester, server);
    final button = find.byKey(const ValueKey('play-list-1'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tapVisible(tester, find.byKey(const ValueKey('delete-list-1')));
    await tester.tap(find.text('Abbrechen'));
    await tester.pumpAndSettle();
    expect(server.lists, hasLength(1));
    await tapVisible(tester, find.byKey(const ValueKey('delete-list-1')));
    await tester.tap(find.text('Löschen'));
    await tester.pumpAndSettle();
    expect(server.lists, isEmpty);
    expect(server.deleted, isEmpty);
    await closeApp(tester);
  });

  testWidgets('playlist creation works on a narrow screen', (tester) async {
    final server = PlaylistServer();
    await openLists(tester, server, width: 320);
    await tapVisible(tester, find.text('Neue Liste'));
    await tester.enterText(find.byKey(const Key('playlist-name')), 'Mobil');
    await tapVisible(tester, find.byType(DropdownButtonFormField<String>));
    await tester.tap(find.text('Angebot.png').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Speichern'));
    await tester.pumpAndSettle();
    expect(server.lists.single['items'], ['Angebot.png']);
    expect(tester.takeException(), isNull);
    await closeApp(tester);
  });
}
