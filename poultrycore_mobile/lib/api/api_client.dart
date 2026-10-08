import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart' show MediaType;

import '../state/token_store.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.message, {this.body});
  final int statusCode;
  final String message;

  /// The decoded (camelCased) error body, when it was JSON. Bulk endpoints
  /// put per-row errors here on a 400/409.
  final Object? body;
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

  /// Told after every successful POST / PUT / DELETE on any client, so caches
  /// of server lists (dropdown options) can drop what is now stale — a
  /// vehicle created a moment ago must be pickable on the Routes form.
  static final List<void Function()> _writeListeners = [];
  static void addWriteListener(void Function() f) {
    if (!_writeListeners.contains(f)) _writeListeners.add(f);
  }

  Future<dynamic> _write(Future<http.Response> Function() run) async {
    final res = await _send(run);
    for (final f in List.of(_writeListeners)) {
      f();
    }
    return res;
  }

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
      _write(() => _http.post(_uri(path, query),
          headers: _headers(), body: body == null ? null : jsonEncode(body)));

  Future<dynamic> put(String path, {Object? body}) => _write(() => _http
      .put(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body)));

  /// [body] for the endpoints that read one on DELETE (a reversal's reason).
  Future<dynamic> delete(String path, {Object? body}) =>
      _write(() => _http.delete(_uri(path), headers: _headers(), body: body == null ? null : jsonEncode(body)));

  /// A multipart upload: one file plus text fields, as the web's FormData
  /// (e.g. POST /Email/Report with a PDF). The request is rebuilt on the
  /// 401 retry because a sent request cannot be sent again.
  Future<dynamic> postFile(
    String path, {
    required String field,
    required List<int> bytes,
    required String filename,
    String contentType = 'application/octet-stream',
    Map<String, String> fields = const {},
  }) =>
      _send(() async {
        final req = http.MultipartRequest('POST', _uri(path))
          ..headers.addAll(_headers(json: false))
          ..fields.addAll(fields)
          ..files.add(http.MultipartFile.fromBytes(field, bytes,
              filename: filename, contentType: _mediaType(contentType)));
        return http.Response.fromStream(await _http.send(req));
      });

  static MediaType? _mediaType(String type) {
    final parts = type.split('/');
    return parts.length == 2 ? MediaType(parts[0], parts[1]) : null;
  }

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
    Object? body;
    try {
      final decoded = jsonDecode(text);
      if (decoded is Map) {
        final m = normalise(decoded) as Map;
        body = m;
        message = (m['message'] ?? m['detail'] ?? m['title'] ?? text).toString();
      } else {
        message = decoded.toString();
      }
    } catch (_) {
      message = text.isEmpty ? 'Request failed (${res.statusCode})' : text;
    }
    throw ApiException(res.statusCode, message, body: body);
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
