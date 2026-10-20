/// Central configuration for the admin panel.
class AppConfig {
  /// Base URL of the backend API (Express + Firestore).
  ///
  /// - For local development:  http://localhost:5000/api
  /// - For a deployed backend:  https://your-domain.com/api
  ///
  /// NOTE: Flutter Web running in Chrome treats "localhost" as the machine
  /// running the browser, which is the same machine in local development.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://localhost:5000/api',
  );

  /// Brand colors taken from the main Legal Services app.
  static const int primaryColorValue = 0xFF002366; // buttonColor (navy)
  static const int secondaryColorValue = 0xFF3498DB; // blue
  static const int accentColorValue = 0xFFEE2D7A; // pink (tabColor)
  static const int backgroundColorValue = 0xFFECF0F1; // light gray
}
