import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

/// Where the Between backend lives.
/// - Optional override at build time (used for native mobile builds):
///     flutter build apk --dart-define=API_BASE=https://your-app.onrender.com
/// - Web build with no override: talk to whatever origin served the page, so
///   the hosted web app (served by the same server at /app) just works with no
///   URL baked in.
/// - Otherwise (local dev on device/emulator): localhost.
const _apiBaseDefine = String.fromEnvironment('API_BASE', defaultValue: '');

Uri resolveApiUri(String path) {
  if (_apiBaseDefine.isNotEmpty) return Uri.parse('$_apiBaseDefine$path');
  if (kIsWeb) return Uri.base.resolve(path); // same origin as the served page
  return Uri.parse('http://localhost:3000$path');
}

class ApiException implements Exception {
  ApiException(this.status, this.message);

  final int status;
  final String message;

  @override
  String toString() => message;
}

/// Thin client for the patient scope of the Between API. Every call is either
/// unauthenticated (login / accept-invite) or carries the patient's own
/// Bearer token — there is no call in this file that can return another
/// patient's data.
class ApiClient {
  String? token;

  Map<String, String> _headers({bool json = false}) => {
        if (json) 'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };

  Future<dynamic> _send(String method, String path, [Object? body]) async {
    final uri = resolveApiUri(path);
    final request = http.Request(method, uri);
    request.headers.addAll(_headers(json: body != null));
    if (body != null) request.body = jsonEncode(body);

    final streamed = await request.send().timeout(const Duration(seconds: 30));
    final response = await http.Response.fromStream(streamed);

    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      data = null;
    }
    if (response.statusCode >= 400) {
      final message = (data is Map && data['error'] is String)
          ? data['error'] as String
          : 'Something went wrong (${response.statusCode}). Please try again.';
      throw ApiException(response.statusCode, message);
    }
    return data;
  }

  Future<dynamic> get(String path) => _send('GET', path);
  Future<dynamic> post(String path, [Object? body]) =>
      _send('POST', path, body ?? const {});
  Future<dynamic> delete(String path) => _send('DELETE', path);

  /// PUT raw bytes (used for the signed audio-upload URL, which authenticates
  /// itself — no Bearer header needed).
  Future<dynamic> putBytes(String path, List<int> bytes, String mime) async {
    final response = await http
        .put(resolveApiUri(path),
            headers: {'Content-Type': mime}, body: bytes)
        .timeout(const Duration(seconds: 60));
    dynamic data;
    try {
      data = jsonDecode(response.body);
    } catch (_) {
      data = null;
    }
    if (response.statusCode >= 400) {
      final message = (data is Map && data['error'] is String)
          ? data['error'] as String
          : 'Upload failed (${response.statusCode}). Please try again.';
      throw ApiException(response.statusCode, message);
    }
    return data;
  }
}
