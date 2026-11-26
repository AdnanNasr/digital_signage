import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/player_status.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
}

class PlayerApi {
  PlayerApi(this.baseUrl, this.token, this.client);

  final Uri baseUrl;
  final String token;
  final http.Client client;

  Future<PlayerStatus> status() => _request('status');
  Future<PlayerStatus> command(PlayerCommand command) =>
      _request(command.path, post: true);

  Future<PlayerStatus> _request(String path, {bool post = false}) async {
    final url = baseUrl.resolve('/api/player/$path');
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
    };
    try {
      final response =
          await (post
                  ? client.post(url, headers: headers)
                  : client.get(url, headers: headers))
              .timeout(const Duration(seconds: 8));
      if (response.statusCode == 401) {
        throw const ApiException(
          'Das Passwort ist ungültig. Bitte erneut anmelden.',
          401,
        );
      }
      if (response.statusCode != 200) {
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
      try {
        return PlayerStatus.fromJson(
          jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>,
        );
      } on Object {
        throw const ApiException(
          'Der Server hat eine ungültige Antwort gesendet.',
        );
      }
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
