import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../models/session.dart';
import 'config.dart';
import 'json.dart';

class ApiException implements Exception {
  final String message;
  final int? statusCode;
  ApiException(this.message, [this.statusCode]);
  @override
  String toString() => message;
}

/// Shared Dio client. Attaches the bearer token, and on a 401 tries one
/// Refresh-Token round-trip before failing (mirrors lib/api/client.ts on web).
class ApiClient {
  ApiClient._();
  static final ApiClient instance = ApiClient._();

  static const _storage = FlutterSecureStorage();
  static const _sessionKey = 'pm_session';

  final Dio dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
    headers: {'Content-Type': 'application/json', 'Accept': 'application/json'},
    validateStatus: (s) => s != null && s < 500,
  ));

  Session? session;
  void Function()? onSessionExpired;

  Future<Session?> restoreSession() async {
    final raw = await _storage.read(key: _sessionKey);
    if (raw == null) return null;
    try {
      session = Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      return session;
    } catch (_) {
      return null;
    }
  }

  Future<void> saveSession(Session s) async {
    session = s;
    await _storage.write(key: _sessionKey, value: jsonEncode(s.toJson()));
  }

  Future<void> clearSession() async {
    session = null;
    await _storage.delete(key: _sessionKey);
  }

  Options get _authOptions =>
      Options(headers: session == null ? {} : {'Authorization': 'Bearer ${session!.token}'});

  Future<dynamic> request(
    String method,
    String url, {
    Object? body,
    Map<String, dynamic>? query,
    bool retryOn401 = true,
  }) async {
    final res = await dio.request(
      url,
      data: body,
      queryParameters: query,
      options: _authOptions.copyWith(method: method),
    );

    if (res.statusCode == 401 && retryOn401 && session != null) {
      final refreshed = await _tryRefresh();
      if (refreshed) return request(method, url, body: body, query: query, retryOn401: false);
      onSessionExpired?.call();
      throw ApiException('Your session has expired. Please sign in again.', 401);
    }

    if (res.statusCode != null && res.statusCode! >= 400) {
      throw ApiException(_errorMessage(res), res.statusCode);
    }
    return res.data;
  }

  Future<bool> _tryRefresh() async {
    final s = session;
    if (s == null || s.refreshToken.isEmpty) return false;
    try {
      final res = await dio.post(
        '${AppConfig.loginApiBaseUrl}/api/Authentication/Refresh-Token',
        data: {
          'accessToken': {'token': s.token, 'expiryTokenDate': DateTime.now().toIso8601String()},
          'refreshToken': {
            'token': s.refreshToken,
            'expiryTokenDate': DateTime.now().add(const Duration(days: 1)).toIso8601String(),
          },
        },
      );
      if (res.statusCode != 200 || res.data is! Map<String, dynamic>) return false;
      final data = res.data as Map<String, dynamic>;
      final inner = pick(data, ['response']) is Map<String, dynamic>
          ? pick(data, ['response']) as Map<String, dynamic>
          : data;
      final access = pick(inner, ['accessToken']);
      final refresh = pick(inner, ['refreshToken']);
      final newToken =
          access is Map<String, dynamic> ? pickString(access, ['token']) : pickString(inner, ['token']);
      if (newToken.isEmpty) return false;
      final newRefresh =
          refresh is Map<String, dynamic> ? pickString(refresh, ['token']) : s.refreshToken;
      await saveSession(s.copyWith(token: newToken, refreshToken: newRefresh));
      return true;
    } catch (_) {
      return false;
    }
  }

  String _errorMessage(Response res) {
    final data = res.data;
    if (data is Map<String, dynamic>) {
      final msg = pickString(data, ['message', 'title', 'error', 'detail']);
      if (msg.isNotEmpty) return msg;
      final errors = pick(data, ['errors']);
      if (errors is Map) {
        final first = errors.values.expand((v) => v is List ? v : [v]).firstOrNull;
        if (first != null) return first.toString();
      }
    }
    if (data is String && data.isNotEmpty && data.length < 300) return data;
    return 'Request failed (${res.statusCode}). Please try again.';
  }
}
