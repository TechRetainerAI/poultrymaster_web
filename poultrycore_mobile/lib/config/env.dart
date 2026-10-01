/// API endpoints.
///
/// Defaults to DEV so a debug build can never write to customer records.
/// Switch with:  flutter run --dart-define=POULTRYCORE_ENV=prod
class Env {
  static const String _name =
      String.fromEnvironment('POULTRYCORE_ENV', defaultValue: 'dev');

  static bool get isProd => _name == 'prod';
  static String get name => _name;

  /// Login / identity service (auth, companies).
  static String get loginApi => isProd
      ? 'https://poultrymaster-api-git-t6tn7geswq-ew.a.run.app'
      : 'https://poultrymaster-login-api-dev-t6tn7geswq-ew.a.run.app';

  /// Farm service (all business modules).
  static String get farmApi => isProd
      ? 'https://poultrymaster-farm-api-git-t6tn7geswq-ew.a.run.app'
      : 'https://poultrymaster-farm-api-dev-t6tn7geswq-ew.a.run.app';

  /// Shown in the UI so a tester is never unsure which data they are looking at.
  static String get banner => isProd ? 'PRODUCTION' : 'DEV';
}
