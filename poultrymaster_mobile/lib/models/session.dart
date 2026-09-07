import '../core/json.dart';

/// Parsed from the Login API's `ApiResponse<LoginResponse>` payload.
class Session {
  final String token;
  final String refreshToken;
  final String userId;
  final String username;
  final String farmId;
  final String farmName;
  final bool isStaff;
  final bool isSubscriber;

  const Session({
    required this.token,
    required this.refreshToken,
    required this.userId,
    required this.username,
    required this.farmId,
    required this.farmName,
    required this.isStaff,
    required this.isSubscriber,
  });

  /// Accepts both the flat and the ApiResponse-wrapped login payloads.
  factory Session.fromLoginPayload(Map<String, dynamic> data) {
    final inner = pick(data, ['response']) is Map<String, dynamic>
        ? pick(data, ['response']) as Map<String, dynamic>
        : data;
    final access = pick(inner, ['accessToken']);
    final refresh = pick(inner, ['refreshToken']);
    final token = access is Map<String, dynamic>
        ? pickString(access, ['token'])
        : pickString(inner, ['token', 'accessToken']);
    final refreshTok = refresh is Map<String, dynamic>
        ? pickString(refresh, ['token'])
        : pickString(inner, ['refreshToken']);
    final userId = pickString(inner, ['userId', 'id']);
    return Session(
      token: token,
      refreshToken: refreshTok,
      userId: userId,
      username: pickString(inner, ['username', 'userName']),
      // Same fallback the web app uses: solo owners have farmId == userId.
      farmId: pickString(inner, ['farmId'], userId),
      farmName: pickString(inner, ['farmName'], 'My Farm'),
      isStaff: pickBool(inner, ['isStaff']),
      isSubscriber: pickBool(inner, ['isSubscriber']),
    );
  }

  Map<String, dynamic> toJson() => {
        'token': token,
        'refreshToken': refreshToken,
        'userId': userId,
        'username': username,
        'farmId': farmId,
        'farmName': farmName,
        'isStaff': isStaff,
        'isSubscriber': isSubscriber,
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        token: j['token'] ?? '',
        refreshToken: j['refreshToken'] ?? '',
        userId: j['userId'] ?? '',
        username: j['username'] ?? '',
        farmId: j['farmId'] ?? '',
        farmName: j['farmName'] ?? '',
        isStaff: j['isStaff'] ?? false,
        isSubscriber: j['isSubscriber'] ?? false,
      );

  Session copyWith({String? token, String? refreshToken}) => Session(
        token: token ?? this.token,
        refreshToken: refreshToken ?? this.refreshToken,
        userId: userId,
        username: username,
        farmId: farmId,
        farmName: farmName,
        isStaff: isStaff,
        isSubscriber: isSubscriber,
      );
}

/// Returned by /api/Authentication/login when the account has 2FA enabled.
class TwoFactorChallenge {
  final String userId;
  final String username;
  final String message;
  const TwoFactorChallenge({required this.userId, required this.username, required this.message});
}
