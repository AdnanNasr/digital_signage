import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/player_status.dart';
import '../models/media_file.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
}

class SignageApi {
  SignageApi(this.baseUrl, this.token, this.client);

  final Uri baseUrl;
  final String token;
  final http.Client client;

  Future<PlayerStatus> status() async => _decode(
    await _request(baseUrl.resolve('/api/player/status')),
    (data) => PlayerStatus.fromJson(data as Map<String, dynamic>),
  );

  Future<PlayerStatus> command(PlayerCommand command) async => _decode(
    await _request(
      baseUrl.resolve('/api/player/${command.path}'),
      method: 'POST',
    ),
    (data) => PlayerStatus.fromJson(data as Map<String, dynamic>),
  );

  Future<List<MediaFile>> media() async => _decode(
    await _request(baseUrl.resolve('/api/media')),
    (data) => (data as List<dynamic>)
        .map((item) => MediaFile.fromJson(item as Map<String, dynamic>))
        .toList(),
  );

  Future<void> deleteMedia(String id) async {
    await _request(
      baseUrl.replace(
        pathSegments: ['api', 'media', id],
        queryParameters: {'confirm': 'true'},
      ),
      method: 'DELETE',
    );
  }

  Future<void> upload(VideoUpload file, void Function(double) onProgress) =>
      file.send(
        baseUrl
            .resolve('/api/media/upload')
            .replace(queryParameters: {'filename': file.name}),
        token,
        onProgress,
      );

  T _decode<T>(http.Response response, T Function(Object?) decode) {
    try {
      return decode(jsonDecode(utf8.decode(response.bodyBytes)));
    } on Object {
      throw const ApiException(
        'Der Server hat eine ungültige Antwort gesendet.',
      );
    }
  }

  Future<http.Response> _request(Uri url, {String method = 'GET'}) async {
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };
    try {
      final response = await (switch (method) {
        'POST' => client.post(url, headers: headers),
        'DELETE' => client.delete(url, headers: headers),
        _ => client.get(url, headers: headers),
      }).timeout(const Duration(seconds: 8));
      if (response.statusCode == 401) {
        throw const ApiException(
          'Das Passwort ist ungültig. Bitte erneut anmelden.',
          401,
        );
      }
      if (response.statusCode != 200 && response.statusCode != 204) {
        String message = 'Die Anfrage konnte nicht ausgeführt werden.';
        try {
          final data = jsonDecode(utf8.decode(response.bodyBytes));
          if (data is Map<String, dynamic> && data['detail'] is String) {
            message = data['detail'] as String;
          }
        } on FormatException {
          // A reverse proxy may return an HTML error page.
        }
        throw ApiException(message, response.statusCode);
      }
      return response;
    } on TimeoutException {
      throw const ApiException(
        'Der Server antwortet nicht. Bitte die Verbindung prüfen.',
      );
    } on http.ClientException {
      throw const ApiException(
        'Keine Verbindung zum Server. Bitte Adresse und Netzwerk prüfen.',
      );
    }
  }
}
