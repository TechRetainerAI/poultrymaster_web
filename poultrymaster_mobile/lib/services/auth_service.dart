import '../core/api_client.dart';
import '../core/config.dart';
import '../core/json.dart';
import '../models/session.dart';

class AuthService {
  static final _api = ApiClient.instance;
  static String get _base => AppConfig.loginApiBaseUrl;

  /// Returns a [Session] on success, or a [TwoFactorChallenge] when the
  /// account requires the emailed OTP code.
  static Future<Object> login(String username, String password) async {
    final data = await _api.request('POST', '$_base/api/Authentication/login',
        body: {'username': username, 'password': password});
    if (data is! Map<String, dynamic>) throw ApiException('Unexpected login response.');

    if (pickBool(data, ['requiresTwoFactor'])) {
      return TwoFactorChallenge(
        userId: pickString(data, ['userId']),
        username: pickString(data, ['username'], username),
        message: pickString(data, ['message'], 'An OTP code was sent to your email.'),
      );
    }
    if (!pickBool(data, ['isSuccess'], true)) {
      throw ApiException(pickString(data, ['message'], 'Invalid username or password.'));
    }
    final session = Session.fromLoginPayload(data);
    if (session.token.isEmpty) throw ApiException('Login succeeded but no token was returned.');
    await _api.saveSession(session);
    return session;
  }

  static Future<Session> verifyOtp(TwoFactorChallenge challenge, String code) async {
    // Backend model binder accepts PascalCase; send both like the web app does.
    final data = await _api.request('POST', '$_base/api/Authentication/login-2FA', body: {
      'userId': challenge.userId,
      'userName': challenge.username,
      'otpCode': code,
      'UserId': challenge.userId,
      'UserName': challenge.username,
      'OtpCode': code,
    });
    if (data is! Map<String, dynamic> || !pickBool(data, ['isSuccess'], true)) {
      throw ApiException(pickString(
          data is Map<String, dynamic> ? data : null, ['message'], 'Invalid OTP code.'));
    }
    final session = Session.fromLoginPayload(data);
    if (session.token.isEmpty) throw ApiException('OTP verified but no token was returned.');
    await _api.saveSession(session);
    return session;
  }

  static Future<String> register({
    required String username,
    required String email,
    required String password,
    required String farmName,
    String? firstName,
    String? lastName,
  }) async {
    final data = await _api.request('POST', '$_base/api/Authentication/Register', body: {
      'username': username,
      'email': email,
      'password': password,
      'firstName': firstName ?? '',
      'lastName': lastName ?? '',
      'roles': ['User'],
      'farmName': farmName,
    });
    return pickString(data is Map<String, dynamic> ? data : null, ['message'],
        'Account created. Check your email to confirm your address, then sign in.');
  }

  static Future<String> forgotPassword(String email) async {
    final data = await _api.request(
        'POST', '$_base/api/Authentication/ForgotPassword?email=${Uri.encodeComponent(email)}',
        body: {'email': email});
    return pickString(data is Map<String, dynamic> ? data : null, ['message'],
        'If that email exists, a reset link has been sent.');
  }

  static Future<void> logout() async {
    try {
      await _api.request('POST', '$_base/api/Authentication/logout', body: {});
    } catch (_) {
      // Local sign-out must succeed even if the server call fails.
    }
    await _api.clearSession();
  }
}
