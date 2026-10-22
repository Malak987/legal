import 'package:flutter_test/flutter_test.dart';
import 'package:legal_admin/config/app_config.dart';

void main() {
  test('AppConfig.apiBaseUrl defaults to deployed Firebase HTTPS endpoint', () {
    final uri = Uri.parse(AppConfig.apiBaseUrl);
    expect(AppConfig.apiBaseUrl, 'https://legal-102026.web.app/api');
    expect(uri.scheme, 'https');
    expect(uri.host, 'legal-102026.web.app');
    expect(uri.path, '/api');
    expect(AppConfig.apiBaseUrl.contains('localhost'), isFalse);
    expect(AppConfig.apiBaseUrl.contains('127.0.0.1'), isFalse);
  });

  test('AppConfig.supabaseUrl defaults to the connected Supabase project without embedding secrets', () {
    final uri = Uri.parse(AppConfig.supabaseUrl);
    expect(AppConfig.supabaseProjectRef, 'qqfzbecwhewswkyxgebu');
    expect(AppConfig.supabaseUrl, 'https://qqfzbecwhewswkyxgebu.supabase.co');
    expect(uri.scheme, 'https');
    expect(uri.host, 'qqfzbecwhewswkyxgebu.supabase.co');
    expect(AppConfig.supabaseAnonKey, isEmpty);
    expect(AppConfig.useSupabase, isFalse);
  });
}
