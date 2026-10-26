import 'supabase_config.dart';

/// Compile-time configuration for the admin panel.
///
/// Supabase values are read ONLY from Dart defines supplied when the app is
/// compiled (`flutter run`/`flutter build web --dart-define=...`, or
/// `scripts/run_web.mjs` / `scripts/build_web.mjs`). Shell or hosting
/// environment variables are not visible to Flutter web at runtime. Validate
/// them through [SupabaseConfig.environment] rather than reading these raw
/// constants directly.
class AppConfig {
  static const String supabaseUrlDefine = 'SUPABASE_URL';
  static const String supabaseAnonKeyDefine = 'SUPABASE_ANON_KEY';

  static const String supabaseProjectRef = String.fromEnvironment(
    'SUPABASE_PROJECT_REF',
    defaultValue: 'qqfzbecwhewswkyxgebu',
  );

  static const String supabaseUrl = String.fromEnvironment(
    supabaseUrlDefine,
    defaultValue: 'https://qqfzbecwhewswkyxgebu.supabase.co',
  );

  /// Public anon/publishable key only. Never embed service-role/secret keys.
  static const String supabaseAnonKey = String.fromEnvironment(
    supabaseAnonKeyDefine,
    defaultValue: '',
  );

  /// Redirect URI for email confirmation and password-recovery links. It must
  /// be explicitly allow-listed in the Supabase Auth settings.
  static const String authRedirectUrl = String.fromEnvironment(
    'SUPABASE_AUTH_REDIRECT_URL',
    defaultValue: '',
  );

  /// Whether the compiled Supabase configuration passed validation.
  static bool get useSupabase => SupabaseConfig.environment.isValid;

  static const int primaryColorValue = 0xFF002366;
  static const int secondaryColorValue = 0xFF3498DB;
  static const int accentColorValue = 0xFFEE2D7A;
  static const int backgroundColorValue = 0xFFECF0F1;
}
