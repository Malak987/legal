/// Compile-time Supabase configuration for the Legal Services mobile app.
///
/// Pass values via `--dart-define` at build or run time:
/// ```bash
/// flutter run \
///   --dart-define=SUPABASE_URL=https://qqfzbecwhewswkyxgebu.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=<your-anon-or-publishable-key> \
///   --dart-define=API_BASE_URL=http://localhost:5000/api
/// ```
///
/// Security invariant: NEVER pass or embed a Supabase `service_role` or
/// `secret` key in Flutter client code. Only the public `anon` / `publishable`
/// key belongs on the client.
class SupabaseConfig {
  const SupabaseConfig._();

  /// Connected Supabase project reference ID.
  static const String projectRef = String.fromEnvironment(
    'SUPABASE_PROJECT_REF',
    defaultValue: 'qqfzbecwhewswkyxgebu',
  );

  /// Connected Supabase project URL.
  static const String supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://qqfzbecwhewswkyxgebu.supabase.co',
  );

  /// Public Supabase anon/publishable key.
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: '',
  );

  /// True when a public Supabase anon key has been supplied for this build.
  static bool get isConfigured =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;
}
