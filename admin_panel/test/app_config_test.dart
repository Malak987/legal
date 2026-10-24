import 'package:flutter_test/flutter_test.dart';
import 'package:legal_admin/config/app_config.dart';

void main() {
  test('unmigrated Express API has no Firebase or localhost fallback', () {
    expect(AppConfig.apiBaseUrl, isEmpty);
  });

  test('Supabase URL is the connected project while credentials remain external', () {
    final uri = Uri.parse(AppConfig.supabaseUrl);
    expect(AppConfig.supabaseProjectRef, 'qqfzbecwhewswkyxgebu');
    expect(AppConfig.supabaseUrl, 'https://qqfzbecwhewswkyxgebu.supabase.co');
    expect(uri.scheme, 'https');
    expect(uri.host, 'qqfzbecwhewswkyxgebu.supabase.co');
    expect(AppConfig.supabaseAnonKey, isEmpty);
    expect(AppConfig.authRedirectUrl, isEmpty);
    expect(AppConfig.useSupabase, isFalse);
  });
}
