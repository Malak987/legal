/// Central configuration for the admin panel.
class AppConfig {
  /// Base URL of the deployed Firebase backend API (Firebase Hosting rewrite ->
  /// Cloud Functions Gen 2 `api` in `us-central1`).
  ///
  /// Production builds target `https://legal-102026.web.app/api` out of the
  /// box so neither the deployed Admin Web Panel nor local browser sessions
  /// depend on a server running on a developer laptop.
  ///
  /// For local Firebase Emulator development, pass `--dart-define` at run time:
  ///
  ///     flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:5000/api
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://legal-102026.web.app/api',
  );

  /// Brand colors taken from the main Legal Services app.
  static const int primaryColorValue = 0xFF002366; // buttonColor (navy)
  static const int secondaryColorValue = 0xFF3498DB; // blue
  static const int accentColorValue = 0xFFEE2D7A; // pink (tabColor)
  static const int backgroundColorValue = 0xFFECF0F1; // light gray
}
