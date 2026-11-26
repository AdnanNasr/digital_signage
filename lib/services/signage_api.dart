import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/player_status.dart';
import '../models/media_file.dart';
import '../models/playlist.dart';

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

  Future<void> upload(MediaUpload file, void Function(double) onProgress) =>
      file.send(
        baseUrl
            .resolve('/api/media/upload')
            .replace(queryParameters: {'filename': file.name}),
        token,
        onProgress,
      );

  Future<Uint8List> preview(String id) async => (await _request(
    baseUrl.replace(pathSegments: ['api', 'media', id, 'preview']),
  )).bodyBytes;

  Future<PlaylistCollection> playlists() async => _decode(
    await _request(baseUrl.resolve('/api/playlists')),
    (data) => PlaylistCollection.fromJson(data as Map<String, dynamic>),
  );

  Future<void> savePlaylist(PlaylistDraft draft, {String? id}) async {
    await _request(
      baseUrl.resolve(id == null ? '/api/playlists' : '/api/playlists/$id'),
      method: id == null ? 'POST' : 'PUT',
      body: draft.toJson(),
    );
  }

  Future<void> selectPlaylist(String? id) async {
    await _request(
      baseUrl.resolve('/api/playlists/selected'),
      method: 'PUT',
      body: {'id': id},
    );
  }

  Future<void> deletePlaylist(String id) async {
    await _request(
      baseUrl
          .resolve('/api/playlists/$id')
          .replace(queryParameters: {'confirm': 'true'}),
      method: 'DELETE',
    );
  }

  Future<void> startPlaylist(String id) async {
    await _request(
      baseUrl.resolve('/api/playlists/$id/start'),
      method: 'POST',
      timeout: const Duration(seconds: 30),
    );
  }

  Future<Map<String, dynamic>> displayRequest(
    String endpoint, {
    String method = 'GET',
    Map<String, Object?>? body,
  }) async => _decode(
    await _request(
      baseUrl.resolve('/api/display/$endpoint'),
      method: method,
      body: body,
      timeout: const Duration(seconds: 40),
    ),
    (data) => data as Map<String, dynamic>,
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

  Future<http.Response> _request(
    Uri url, {
    String method = 'GET',
    Map<String, Object?>? body,
    Duration timeout = const Duration(seconds: 8),
  }) async {
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json; charset=utf-8',
    };
    try {
      final response = await (switch (method) {
        'POST' => client.post(
          url,
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        ),
        'PUT' => client.put(url, headers: headers, body: jsonEncode(body)),
        'DELETE' => client.delete(url, headers: headers),
        _ => client.get(url, headers: headers),
      }).timeout(timeout);
      if (response.statusCode == 401) {
        throw const ApiException(
          'Das Passwort ist ungültig. Bitte erneut anmelden.',
          401,
        );
      }
      if (![200, 201, 204].contains(response.statusCode)) {
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
