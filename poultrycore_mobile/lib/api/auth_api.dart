import '../state/token_store.dart';
import 'api_client.dart';

/// Outcome of a login attempt. The backend has three distinct success-ish
/// states, so a bool is not enough.
class LoginOutcome {
  LoginOutcome.success()
      : requiresTwoFactor = false,
        ok = true,
        message = null,
        userId = null,
        username = null;

  LoginOutcome.twoFactor({this.userId, this.username, this.message})
      : requiresTwoFactor = true,
        ok = false;

  LoginOutcome.failure(this.message)
      : requiresTwoFactor = false,
        ok = false,
        userId = null,
        username = null;

  final bool ok;
  final bool requiresTwoFactor;
  final String? message;
  final String? userId;
  final String? username;
}

/// A Business Office resolved from its code.
class OrgRef {
  const OrgRef({required this.ownerUserId, this.businessOfficeName});
  final String ownerUserId;
  final String? businessOfficeName;
}

class AuthApi {
  AuthApi(this._client, this._tokens);

  final ApiClient _client;
  final TokenStore _tokens;

  /// POST /api/Authentication/login
  ///
  /// Success can mean "signed in" OR "OTP emailed, now call [verifyTwoFactor]".
  /// The flag comes back as either `RequiresTwoFactor` or `requiresTwoFactor`
  /// depending on the path, hence the normalisation pass upstream.
  Future<LoginOutcome> login({
    required String username,
    required String password,
    bool rememberMe = true,
  }) async {
    try {
      final res = await _client.post('/api/Authentication/login', body: {
        'username': username,
        'password': password,
        'rememberMe': rememberMe,
      });

      if (res is! Map) return LoginOutcome.failure('Unexpected response from server.');
      final map = Map<String, dynamic>.from(res);

      if (map['requiresTwoFactor'] == true) {
        return LoginOutcome.twoFactor(
          userId: map['userId']?.toString(),
          username: map['username']?.toString() ?? username,
          message: map['message']?.toString() ?? 'A code was sent to your email.',
        );
      }

      if (map['isSuccess'] != true) {
        return LoginOutcome.failure(map['message']?.toString() ?? 'Login failed.');
      }

      await _persist(map);
      return LoginOutcome.success();
    } on ApiException catch (e) {
      return LoginOutcome.failure(e.message);
    }
  }

  /// POST /api/Authentication/login-2FA
  Future<LoginOutcome> verifyTwoFactor({
    required String username,
    required String code,
  }) async {
    try {
      final res = await _client.post('/api/Authentication/login-2FA',
          query: {'code': code, 'username': username});
      if (res is! Map) return LoginOutcome.failure('Unexpected response from server.');
      final map = Map<String, dynamic>.from(res);
      if (map['isSuccess'] != true) {
        return LoginOutcome.failure(map['message']?.toString() ?? 'That code was not accepted.');
      }
      await _persist(map);
      return LoginOutcome.success();
    } on ApiException catch (e) {
      return LoginOutcome.failure(e.message);
    }
  }

  /// POST /api/Authentication/Refresh-Token — wired into [ApiClient] so any
  /// 401 retries once before the user is bounced to the login screen.
  Future<bool> refresh() async {
    final access = _tokens.accessToken;
    final refreshToken = _tokens.refreshToken;
    if ((refreshToken ?? '').isEmpty) return false;

    try {
      final res = await _client.post('/api/Authentication/Refresh-Token', body: {
        'accessToken': access,
        'refreshToken': refreshToken,
      });
      if (res is! Map) return false;
      final map = Map<String, dynamic>.from(res);
      final payload = map['response'] is Map
          ? Map<String, dynamic>.from(map['response'] as Map)
          : map;
      final newAccess = _tokenOf(payload['accessToken']);
      if (newAccess == null) return false;
      await _tokens.saveTokens(
        access: newAccess,
        refresh: _tokenOf(payload['refreshToken']),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  /// GET /api/Authentication/org?code=XXX
  ///
  /// Resolves a Business Office code to the organisation that owns it. The web
  /// uses this to scope the company list: only companies whose `ownerUserId`
  /// matches are shown, and a code that resolves to nothing (or to an org the
  /// user has no companies in) is treated as a mismatch rather than ignored.
  Future<OrgRef?> resolveOrgCode(String code) async {
    if (code.isEmpty) return null;
    try {
      final res =
          await _client.get('/api/Authentication/org', query: {'code': code});
      if (res is! Map) return null;
      final map = Map<String, dynamic>.from(res);
      if (map['found'] != true) return null;
      return OrgRef(
        ownerUserId: '${map['ownerUserId'] ?? ''}',
        businessOfficeName: map['businessOfficeName']?.toString(),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> logout() async {
    try {
      await _client.post('/api/Authentication/logout');
    } catch (_) {
      // A failed server-side logout must not strand the user in the app.
    }
    await _tokens.clear();
  }

  /// The login response nests the real payload under `response` on some paths
  /// and returns it flat on others.
  Future<void> _persist(Map<String, dynamic> map) async {
    final payload =
        map['response'] is Map ? Map<String, dynamic>.from(map['response'] as Map) : map;

    await _tokens.saveTokens(
      access: _tokenOf(payload['accessToken']),
      refresh: _tokenOf(payload['refreshToken']),
    );
    await _tokens.saveUser(
      userId: payload['userId']?.toString(),
      username: payload['username']?.toString() ?? payload['userName']?.toString(),
    );
    // Deliberately NOT saving farmId/farmName from the login response.
    //
    // The response carries a farm, but the web calls clearActiveCompany() on
    // sign-in (Doc 3 §4/§9) so everyone lands company-neutral and chooses.
    // Persisting it here would silently drop the user into whichever company
    // the token happened to name — which is what this app did before, landing
    // on a company the user never picked.
    await _tokens.saveFarm(farmId: '', farmName: '');
  }

  /// Tokens arrive as `{token, expiryTokenDate}` but occasionally as a string.
  static String? _tokenOf(dynamic node) {
    if (node == null) return null;
    if (node is String) return node.isEmpty ? null : node;
    if (node is Map) {
      final t = node['token'];
      if (t is String && t.isNotEmpty) return t;
    }
    return null;
  }
}
