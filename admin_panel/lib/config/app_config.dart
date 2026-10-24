/// Compile-time configuration for the admin panel.
class AppConfig {
  /// Optional URL for still-legacy Express endpoints, now backed by Supabase.
  /// No Firebase Hosting endpoint is used as a silent fallback.
  static const String apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static const String supabaseProjectRef = String.fromEnvironment(
    'SUPABASE_PROJECT_REF',
    defaultValue: 'qqfzbecwhewswkyxgebu',
  );

  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qqfzbecwhewswkyxgebu.supabase.co',
  );

  /// Public anon/publishable key only. Never embed service-role/secret keys.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// Redirect URI for email confirmation and password-recovery links. It must
  /// be explicitly allow-listed in the Supabase Auth settings.
  static const String authRedirectUrl = String.fromEnvironment(
    'SUPABASE_AUTH_REDIRECT_URL',
    defaultValue: '',
  );

  static bool get useSupabase =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  static const int primaryColorValue = 0xFF002366;
  static const int secondaryColorValue = 0xFF3498DB;
  static const int accentColorValue = 0xFFEE2D7A;
  static const int backgroundColorValue = 0xFFECF0F1;
}
