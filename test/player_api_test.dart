import 'dart:convert';

import 'package:digital_signage/models/player_status.dart';
import 'package:digital_signage/services/signage_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'lists media and encodes filenames safely for confirmed deletion',
    () async {
      const name = 'Grüße & #?.mp4';
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return request.method == 'DELETE'
            ? http.Response('', 204)
            : http.Response(
                jsonEncode([
                  {'id': name, 'name': name, 'size_bytes': 2048},
                ]),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
      });
      addTearDown(client.close);
      final api = SignageApi(Uri.parse('http://pi.local'), 'password', client);
      expect((await api.media()).single.name, name);
      await api.deleteMedia(name);
      expect(requests.last.url.pathSegments, ['api', 'media', name]);
      expect(requests.last.url.queryParameters, {'confirm': 'true'});
      expect(requests.last.url.hasFragment, isFalse);
      expect(requests.last.headers['Authorization'], 'Bearer password');
    },
  );

  test(
    'uses authenticated GET and POST without putting the token in the URL',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode({
            'state': 'paused',
            'reachable': true,
            'video_count': 3,
            'current_file': 'Grüße.mp4',
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      addTearDown(client.close);
      final api = SignageApi(
        Uri.parse('http://pi.local:8000/'),
        'secret',
        client,
      );
      expect((await api.status()).currentFile, 'Grüße.mp4');
      await api.command(PlayerCommand.resume);
      expect(requests.map((request) => request.method), ['GET', 'POST']);
      expect(
        requests.last.url.toString(),
        'http://pi.local:8000/api/player/resume',
      );
      expect(requests.last.headers['Authorization'], 'Bearer secret');
      expect(requests.last.url.hasQuery, isFalse);
    },
  );

  test(
    'preserves German server errors and handles malformed responses',
    () async {
      for (final response in [
        http.Response('{"detail":"Keine Videos vorhanden."}', 409),
        http.Response('<html>Bad Gateway</html>', 502),
        http.Response('{"unexpected":true}', 200),
        http.Response('{}', 401),
      ]) {
        final client = MockClient((_) async => response);
        final api = SignageApi(Uri.parse('http://pi.local'), 'secret', client);
        await expectLater(api.status(), throwsA(isA<ApiException>()));
        client.close();
      }
      final client = MockClient(
        (_) async => http.Response('{"detail":"Keine Videos vorhanden."}', 409),
      );
      addTearDown(client.close);
      await expectLater(
        SignageApi(Uri.parse('http://pi.local'), 'secret', client).status(),
        throwsA(
          isA<ApiException>().having(
            (error) => error.message,
            'message',
            'Keine Videos vorhanden.',
          ),
        ),
      );
    },
  );
}
