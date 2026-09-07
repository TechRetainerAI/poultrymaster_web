/// Backend hosts. The mobile app talks to the Cloud Run services directly
/// (no same-origin proxy like the web app needs).
class AppConfig {
  static const String loginApiBaseUrl =
      String.fromEnvironment('LOGIN_API', defaultValue: 'https://usermanagementapi.poultrycore.com');
  static const String farmApiBaseUrl =
      String.fromEnvironment('FARM_API', defaultValue: 'https://farmapi.poultrycore.com');

  static const String appName = 'PoultryMaster';
  static const String currencySymbol = '\$';
}
