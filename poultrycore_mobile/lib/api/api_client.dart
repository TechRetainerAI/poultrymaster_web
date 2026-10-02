import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../state/token_store.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message);
  final int statusCode;
  final String message;
  @override
  String toString() => 'ApiException($statusCode): $message';
}

/// Shared HTTP layer for both services.
///
/// Two behaviours here exist because the backend requires them, not because
/// they are conventional:
///
/// 1. The APIs return **PascalCase** JSON (they are serialised straight off the
///    C# models). The web client lowercases defensively because some endpoints
///    return camelCase instead. We do the same — see [normalise].
///
/// 2. Access tokens last 60 minutes. A 401 mid-session is normal, not a login
///    failure, so one refresh-then-retry is attempted before surfacing an
///    error. Without this the user gets logged out while actively using the app.
class ApiClient {
  ApiClient({required this.baseUrl, required this.tokens, http.Client? inner})
      : _http = inner ?? http.Client();

  final String baseUrl;
  final TokenStore tokens;
  final http.Client _http;

  /// Called when refresh fails and the session is genuinely over.
  void Function()? onAuthLost;

  /// Set by the auth layer so this client can refresh without a circular import.
  Future<bool> Function()? refreshCallback;

  Uri _uri(String path, [Map<String, dynamic>? query]) {
    final normalisedPath = path.startsWith('/') ? path : '/$path';
    final cleaned = <String, String>{};
    query?.forEach((k, v) {
      if (v != null) cleaned[k] = '$v';
    });
    return Uri.parse('$baseUrl$normalisedPath')
        .replace(queryParameters: cleaned.isEmpty ? null : cleaned);
  }

  Map<String, String> _headers({bool json = true}) {
    final token = tokens.accessToken;
    return {
      'accept': '*/*',
      if (json) 'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<dynamic> get(String path, {Map<String, dynamic>? query}) =>
      _send(() => _http.get(_uri(path, query), headers: _headers()));

  Future<dynamic> post(String path, {Object? body, Map<String, dynamic>? query}) =>
      _send(() => _http.post(_uri(path, query),
          headers: _headers(), body: body == null ? null : jsonEncode(body)));

  Future<dynamic> put(String path, {Object? body}) => _send(() => _http
      .put(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body)));

  Future<dynamic> delete(String path) =>
      _send(() => _http.delete(_uri(path), headers: _headers()));

  /// Sends, and on a 401 refreshes once and replays the request.
  Future<dynamic> _send(Future<http.Response> Function() run) async {
    http.Response res;
    try {
      res = await run().timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw ApiException(0, 'The server took too long to respond.');
    } catch (e) {
      throw ApiException(0, 'Network error. Check your connection.');
    }

    if (res.statusCode == 401 && refreshCallback != null) {
      final ok = await refreshCallback!();
      if (ok) {
        try {
          res = await run().timeout(const Duration(seconds: 45));
        } on TimeoutException {
          throw ApiException(0, 'The server took too long to respond.');
        }
      } else {
        onAuthLost?.call();
      }
    }

    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    final text = res.body.trim();

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (text.isEmpty) return null;
      try {
        return normalise(jsonDecode(text));
      } on FormatException {
        return text;
      }
    }

    // Error bodies are inconsistent across controllers: sometimes a bare
    // string, sometimes {message}, sometimes ProblemDetails {title, detail}.
    String message;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final m = normalise(decoded) as Map;
        message = (m['message'] ?? m['detail'] ?? m['title'] ?? text).toString();
      } else {
        message = decoded.toString();
      }
    } catch (_) {
      message = text.isEmpty ? 'Request failed (${res.statusCode})' : text;
    }
    throw ApiException(res.statusCode, message);
  }

  /// Recursively lower-cases the first letter of every key.
  ///
  /// The APIs are inconsistent — `/Companies/mine` returns PascalCase while
  /// most farm endpoints return camelCase — so every model in this app reads
  /// camelCase and relies on this pass.
  static dynamic normalise(dynamic value) {
    if (value is List) return value.map(normalise).toList();
    if (value is Map) {
      return value.map((k, v) {
        final key = k is String && k.isNotEmpty
            ? k[0].toLowerCase() + k.substring(1)
            : k;
        return MapEntry(key, normalise(v));
      });
    }
    return value;
  }

  void close() => _http.close();
}
