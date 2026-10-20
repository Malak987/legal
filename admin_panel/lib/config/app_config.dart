/// Central configuration for the admin panel.
class AppConfig {
  /// Base URL of the backend API (Express + Firestore).
  ///
  /// The default targets the loopback interface, which is correct whenever the
  /// browser and the backend run on the same machine (the normal local
  /// development setup). A hard-coded LAN IP such as 10.0.0.28 breaks as soon
  /// as the machine's DHCP lease changes — the symptom is
  /// `ClientException: Failed to fetch`.
  ///
  /// For any other target, pass the URL at build/run time instead of editing
  /// this file:
  ///
  ///     flutter run -d chrome --dart-define=API_BASE_URL=http://10.74.140.190:5000/api
  ///     flutter build web  --dart-define=API_BASE_URL=https://api.example.com/api
  ///
  /// NOTE: Flutter Web running in Chrome treats "localhost"/"127.0.0.1" as the
  /// machine running the browser, which is the same machine in local
  /// development.
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:5000/api',
  );

  /// Brand colors taken from the main Legal Services app.
  static const int primaryColorValue = 0xFF002366; // buttonColor (navy)
  static const int secondaryColorValue = 0xFF3498DB; // blue
  static const int accentColorValue = 0xFFEE2D7A; // pink (tabColor)
  static const int backgroundColorValue = 0xFFECF0F1; // light gray
}
