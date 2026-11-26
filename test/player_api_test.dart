import 'dart:convert';

import 'package:digital_signage/models/player_status.dart';
import 'package:digital_signage/services/player_api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
      final api = PlayerApi(
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
        final api = PlayerApi(Uri.parse('http://pi.local'), 'secret', client);
        await expectLater(api.status(), throwsA(isA<ApiException>()));
        client.close();
      }
      final client = MockClient(
        (_) async => http.Response('{"detail":"Keine Videos vorhanden."}', 409),
      );
      addTearDown(client.close);
      await expectLater(
        PlayerApi(Uri.parse('http://pi.local'), 'secret', client).status(),
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
