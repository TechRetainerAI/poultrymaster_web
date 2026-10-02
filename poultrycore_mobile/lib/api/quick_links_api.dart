import 'api_client.dart';

/// The user's Quick Links bar — the shortcuts they chose for one company
/// (migration 318, `api/UserQuickLinks`).
///
/// The web renders this same bar in three places: the sidebar, the desktop
/// rail and the mobile "More" sheet. This app shows it at the top of More, so
/// a phone user reaches their own shortcuts in the same place they would on a
/// phone browser.
class UserQuickLinks {
  const UserQuickLinks({required this.customised, required this.hrefs});

  /// Whether the user has ever chosen. Read THIS, not `hrefs.isEmpty`:
  /// never-chosen and deliberately-cleared are different states and the bar
  /// must not collapse them — an empty bar the user cleared should stay empty
  /// rather than silently reverting to defaults.
  final bool customised;

  final List<String> hrefs;

  static UserQuickLinks fromJson(Map<String, dynamic> j) {
    final raw = j['hrefs'];
    return UserQuickLinks(
      customised: j['customised'] == true,
      hrefs: raw is List
          ? raw.map((e) => '$e').where((e) => e.startsWith('/')).toList()
          : const [],
    );
  }
}

class QuickLinksApi {
  QuickLinksApi(this._farm);

  final ApiClient _farm;

  /// Null when the company or user is unknown, or the call fails. The bar is a
  /// convenience, so a failure hides it rather than blocking the More sheet.
  Future<UserQuickLinks?> get({
    required String? userId,
    required String? farmId,
  }) async {
    if (userId == null || userId.isEmpty) return null;
    if (farmId == null || farmId.isEmpty) return null;
    try {
      final res = await _farm.get(
        '/api/UserQuickLinks',
        query: {'userId': userId, 'farmId': farmId},
      );
      // `ApiClient.normalise` rebuilds maps with Map.map(), which drops the
      // type arguments — the result is a Map<dynamic, dynamic>, so testing for
      // Map<String, dynamic> here never matches and would silently hide the
      // bar. Accept any Map and convert.
      if (res is Map) return UserQuickLinks.fromJson(Map<String, dynamic>.from(res));
      return null;
    } catch (_) {
      return null;
    }
  }
}
