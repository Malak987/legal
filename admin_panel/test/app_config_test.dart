import 'package:flutter_test/flutter_test.dart';
import 'package:legal_admin/config/app_config.dart';
import 'package:legal_admin/config/supabase_config.dart';

void main() {
  test('Supabase URL is the connected project while credentials remain external', () {
    final uri = Uri.parse(AppConfig.supabaseUrl);
    expect(AppConfig.supabaseProjectRef, 'qqfzbecwhewswkyxgebu');
    expect(AppConfig.supabaseUrl, 'https://qqfzbecwhewswkyxgebu.supabase.co');
    expect(uri.scheme, 'https');
    expect(uri.host, 'qqfzbecwhewswkyxgebu.supabase.co');
    expect(AppConfig.authRedirectUrl, isEmpty);
    // No key is ever committed: it exists only when the build passes
    // --dart-define=SUPABASE_ANON_KEY=..., and useSupabase follows validation.
    if (!const bool.hasEnvironment('SUPABASE_ANON_KEY')) {
      expect(AppConfig.supabaseAnonKey, isEmpty);
    }
    expect(AppConfig.useSupabase, SupabaseConfig.environment.isValid);
  });

  test('Dart define names are the ones used by scripts and CI', () {
    expect(AppConfig.supabaseUrlDefine, 'SUPABASE_URL');
    expect(AppConfig.supabaseAnonKeyDefine, 'SUPABASE_ANON_KEY');
  });
}
