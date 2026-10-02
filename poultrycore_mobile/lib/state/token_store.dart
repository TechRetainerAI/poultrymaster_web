import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persists the session across app restarts.
///
/// Key names mirror the web client (`auth_token`, `refresh_token`) so the two
/// stay recognisable to anyone debugging both.
class TokenStore {
  TokenStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kAccess = 'auth_token';
  static const _kRefresh = 'refresh_token';
  static const _kUsername = 'username';
  static const _kUserId = 'user_id';
  static const _kFarmId = 'farm_id';
  static const _kFarmName = 'farm_name';
  static const _kPermissions = 'feature_permissions';

  /// The Business Office code, kept only when "Remember me" was ticked — the
  /// web stores it under this name and pre-fills the field from it.
  static const _kOrgCode = 'remembered_org_code';

  static Future<TokenStore> open() async =>
      TokenStore(await SharedPreferences.getInstance());

  String? get accessToken => _prefs.getString(_kAccess);
  String? get refreshToken => _prefs.getString(_kRefresh);
  String? get username => _prefs.getString(_kUsername);
  String? get userId => _prefs.getString(_kUserId);
  String? get farmId => _prefs.getString(_kFarmId);
  String? get farmName => _prefs.getString(_kFarmName);

  bool get hasSession => (accessToken ?? '').isNotEmpty;

  Future<void> saveTokens({String? access, String? refresh}) async {
    if (access != null && access.isNotEmpty) await _prefs.setString(_kAccess, access);
    if (refresh != null && refresh.isNotEmpty) {
      await _prefs.setString(_kRefresh, refresh);
    }
  }

  Future<void> saveUser({String? userId, String? username}) async {
    if (userId != null) await _prefs.setString(_kUserId, userId);
    if (username != null) await _prefs.setString(_kUsername, username);
  }

  /// The active company. Note the farm context lives inside the JWT — switching
  /// company issues a NEW access token — so this is only for display and for
  /// endpoints that take farmId as a parameter.
  Future<void> saveFarm({String? farmId, String? farmName}) async {
    if (farmId != null) await _prefs.setString(_kFarmId, farmId);
    if (farmName != null) await _prefs.setString(_kFarmName, farmName);
  }

  List<String> get permissions {
    final raw = _prefs.getString(_kPermissions);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => '$e').toList();
    } catch (_) {}
    return const [];
  }

  Future<void> savePermissions(List<String> values) =>
      _prefs.setString(_kPermissions, jsonEncode(values));

  String? get rememberedOrgCode => _prefs.getString(_kOrgCode);

  /// Remembered only on "Remember me"; otherwise any previous code is forgotten,
  /// which is what the web does.
  Future<void> saveOrgCode(String? code, {required bool remember}) async {
    if (remember && (code ?? '').isNotEmpty) {
      await _prefs.setString(_kOrgCode, code!);
    } else {
      await _prefs.remove(_kOrgCode);
    }
  }

  Future<void> clear() async {
    for (final k in [
      _kAccess,
      _kRefresh,
      _kUsername,
      _kUserId,
      _kFarmId,
      _kFarmName,
      _kPermissions,
    ]) {
      await _prefs.remove(k);
    }
  }
}
