import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../models/media_file.dart';
import 'signage_api.dart';

Future<MediaUpload?> pickMedia() {
  final result = Completer<MediaUpload?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.jpg,.jpeg,.png,.webp,.mp4,.mkv,.mov,.webm'
    ..style.display = 'none';
  void finish(MediaUpload? value) {
    if (!result.isCompleted) result.complete(value);
    input.remove();
  }

  input.onchange = ((web.Event event) {
    final file = input.files?.item(0);
    finish(file == null ? null : _BrowserMedia(file));
  }).toJS;
  input.addEventListener('cancel', ((web.Event event) => finish(null)).toJS);
  web.document.body!.appendChild(input);
  input.click();
  return result.future;
}

class _BrowserMedia implements MediaUpload {
  _BrowserMedia(this.file);
  final web.File file;
  web.XMLHttpRequest? _request;

  @override
  String get name => file.name;
  @override
  int get size => file.size;

  @override
  Future<void> send(
    Uri url,
    String token,
    void Function(double) onProgress,
  ) async {
    final result = Completer<void>();
    final request = web.XMLHttpRequest();
    _request = request;
    void fail(String message, [int? code]) {
      if (!result.isCompleted) {
        result.completeError(ApiException(message, code));
      }
    }

    request.upload.onprogress = ((web.ProgressEvent event) {
      if (event.lengthComputable && event.total > 0) {
        onProgress((event.loaded / event.total).clamp(0, 1));
      }
    }).toJS;
    request.upload.onload = ((web.Event event) => onProgress(1)).toJS;
    request.onload = ((web.Event event) {
      if (request.status == 201) {
        if (!result.isCompleted) result.complete();
      } else if (request.status == 401) {
        fail('Das Passwort ist ungültig. Bitte erneut anmelden.', 401);
      } else {
        var message = 'Die Datei konnte nicht hochgeladen werden.';
        try {
          final data = jsonDecode(request.responseText);
          if (data is Map<String, dynamic> && data['detail'] is String) {
            message = data['detail'] as String;
          }
        } on FormatException {
          // A proxy may send an HTML error page.
        }
        fail(message, request.status);
      }
    }).toJS;
    request.onerror = ((web.Event event) => fail(
      'Keine Verbindung zum Server.',
    )).toJS;
    request.onabort = ((web.Event event) => fail('Upload abgebrochen.')).toJS;
    request.ontimeout = ((web.Event event) => fail(
      'Der Upload hat zu lange gedauert.',
    )).toJS;
    try {
      request.open('POST', url.toString());
      request.timeout = 30 * 60 * 1000;
      request.setRequestHeader('Authorization', 'Bearer $token');
      request.setRequestHeader('Content-Type', 'application/octet-stream');
      request.send(file);
      await result.future;
    } finally {
      request.upload.onprogress = null;
      request.upload.onload = null;
      request.onload = null;
      request.onerror = null;
      request.onabort = null;
      request.ontimeout = null;
      _request = null;
    }
  }

  @override
  void cancel() => _request?.abort();
}
