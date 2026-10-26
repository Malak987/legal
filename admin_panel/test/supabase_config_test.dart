import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legal_admin/config/supabase_config.dart';
import 'package:legal_admin/main.dart';
import 'package:legal_admin/screens/login_screen.dart';
import 'package:legal_admin/services/api_service.dart';
import 'package:legal_admin/services/auth_service.dart';

import 'fakes.dart';

// Test-only fixtures. None of these is a real project credential.
const _url = 'https://qqfzbecwhewswkyxgebu.supabase.co';
const _publishable = 'sb_publishable_TESTONLY_not_a_real_key_0000';

String _jwt(Map<String, Object?> claims) {
  String part(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part({'alg': 'HS256', 'typ': 'JWT'})}.${part(claims)}.test-signature';
}

SupabaseConfig _resolve(String url, String key, {bool strict = true}) =>
    SupabaseConfig.resolve(
      url: url,
      anonKey: key,
      requireKnownKeyFormat: strict,
    );

void main() {
  group('SupabaseConfig.resolve', () {
    test('accepts the project URL with a publishable key', () {
      final config = _resolve('$_url/', _publishable);
      expect(config.isValid, isTrue);
      expect(config.issues, isEmpty);
      expect(config.url, _url, reason: 'trailing slash is normalized');
      expect(config.anonKey, _publishable);
      expect(config.errorMessage, isEmpty);
    });

    test('accepts a legacy anon JWT for the same project', () {
      final key = _jwt({'role': 'anon', 'ref': 'qqfzbecwhewswkyxgebu'});
      expect(_resolve(_url, key).isValid, isTrue);
    });

    test('allows http only for a local Supabase stack', () {
      expect(_resolve('http://127.0.0.1:54321', _publishable).isValid, isTrue);
      expect(_resolve('http://localhost:54321', _publishable).isValid, isTrue);
      expect(
        _resolve(
          'http://qqfzbecwhewswkyxgebu.supabase.co',
          _publishable,
        ).issues,
        [SupabaseConfigIssue.insecureUrl],
      );
    });

    test('reports a missing URL', () {
      expect(_resolve('', _publishable).issues, [
        SupabaseConfigIssue.missingUrl,
      ]);
    });

    test('reports a missing key', () {
      expect(_resolve(_url, '').issues, [SupabaseConfigIssue.missingKey]);
    });

    test('treats whitespace-only values as empty', () {
      expect(_resolve('   ', ' \n ').issues, [
        SupabaseConfigIssue.missingUrl,
        SupabaseConfigIssue.missingKey,
      ]);
    });

    test('rejects malformed URLs', () {
      const malformed = <String>[
        'qqfzbecwhewswkyxgebu.supabase.co', // no scheme
        'ftp://qqfzbecwhewswkyxgebu.supabase.co',
        'https://',
        '$_url/rest/v1', // endpoint instead of the project base URL
        '$_url/auth/v1',
        '$_url?apikey=x',
        '$_url#fragment',
        'https://user:pass@qqfzbecwhewswkyxgebu.supabase.co',
        'not a url',
      ];
      for (final url in malformed) {
        expect(_resolve(url, _publishable).issues, [
          SupabaseConfigIssue.malformedUrl,
        ], reason: url);
      }
    });

    test('rejects placeholders and the old CI dummy key', () {
      final placeholders = <String>[
        '<public anon/publishable key>',
        SupabaseConfig.legacyCiPlaceholderKey,
        'sb_publishable_',
        'sb_publishable_short',
        'anon-key',
        _jwt({'role': 'authenticated'}),
      ];
      for (final key in placeholders) {
        expect(_resolve(_url, key).issues, [
          SupabaseConfigIssue.malformedKey,
        ], reason: SupabaseConfig.resolve(url: _url, anonKey: key).redactedKey);
      }
    });

    test('rejects secret and service-role keys in every mode', () {
      for (final strict in [true, false]) {
        expect(
          _resolve(
            _url,
            'sb_secret_TESTONLY_0000000000',
            strict: strict,
          ).issues,
          [SupabaseConfigIssue.secretKey],
        );
        expect(
          _resolve(_url, _jwt({'role': 'service_role'}), strict: strict).issues,
          [SupabaseConfigIssue.secretKey],
        );
      }
    });

    test('detects a legacy key from another project', () {
      final key = _jwt({'role': 'anon', 'ref': 'otherprojectref00000'});
      expect(_resolve(_url, key).issues, [SupabaseConfigIssue.projectMismatch]);
    });

    test('test-injection mode skips only the key-format check', () {
      expect(_resolve(_url, 'test-anon-key', strict: false).isValid, isTrue);
      expect(_resolve('', 'test-anon-key', strict: false).issues, [
        SupabaseConfigIssue.missingUrl,
      ]);
    });
  });

  group('error messages', () {
    test('name the define to pass and how to apply it', () {
      final message = _resolve(_url, '').errorMessage;
      expect(message, startsWith('Supabase authentication is not configured.'));
      expect(message, contains('SUPABASE_ANON_KEY is empty'));
      expect(message, contains('--dart-define'));
      expect(message, contains('node scripts/run_web.mjs'));
      expect(message, contains('Hot restart'));
      expect(
        _resolve('', _publishable).errorMessage,
        contains('SUPABASE_URL is empty'),
      );
    });

    test('never contain the key value', () {
      const marker = 'SENSITIVE0123456789abcdef';
      final keys = <String>[
        'sb_publishable_$marker',
        'sb_secret_$marker',
        '<$marker>',
        _jwt({'role': 'service_role', 'marker': marker}),
      ];
      for (final key in keys) {
        for (final url in [_url, '', 'https://bad/path?x']) {
          final config = SupabaseConfig.resolve(url: url, anonKey: key);
          final encodedMarker = key.contains('.') ? key.split('.')[1] : marker;
          for (final text in [
            config.errorMessage,
            config.toString(),
            config.redactedKey,
            ...config.issueDescriptions,
          ]) {
            expect(text.contains(marker), isFalse);
            expect(text.contains(encodedMarker), isFalse);
          }
        }
      }
    });

    test('redactedKey reports only the kind and length', () {
      expect(
        _resolve(_url, _publishable).redactedKey,
        'sb_publishable_… (${_publishable.length} chars)',
      );
      expect(_resolve(_url, '').redactedKey, '(missing)');
    });
  });

  group('compile-time defines', () {
    // Run once without defines (CI default) and once with
    // --dart-define=SUPABASE_ANON_KEY=<fake publishable key> to prove the
    // value reaches the app only through the compile-time define.
    test('SupabaseConfig.environment reflects SUPABASE_ANON_KEY', () {
      final environment = SupabaseConfig.environment;
      expect(
        identical(environment, SupabaseConfig.environment),
        isTrue,
        reason: 'validated once and shared',
      );
      if (const bool.hasEnvironment('SUPABASE_ANON_KEY')) {
        expect(environment.isValid, isTrue, reason: environment.toString());
      } else {
        expect(environment.issues, contains(SupabaseConfigIssue.missingKey));
        expect(environment.errorMessage, contains('SUPABASE_ANON_KEY'));
      }
    });

    test('select() shares one instance unless a test overrides values', () {
      final config = _resolve(_url, _publishable);
      expect(identical(SupabaseConfig.select(config: config), config), isTrue);
      expect(
        identical(SupabaseConfig.select(), SupabaseConfig.environment),
        isTrue,
      );
    });
  });

  group('single shared client configuration', () {
    test('AuthService hands its validated config to its ApiService', () {
      final config = _resolve(_url, _publishable);
      final auth = AuthService(
        config: config,
        supabaseHttpClient: MockClient((_) async => http.Response('{}', 200)),
        sessionStore: MemoryAdminSessionStore(),
      );
      expect(identical(auth.api.config, config), isTrue);
      expect(auth.isConfigured, isTrue);
      expect(auth.api.isConfigured, isTrue);
    });

    test('an invalid config fails fast without any network request', () async {
      var requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('{}', 200);
      });
      final config = _resolve(_url, '');
      final api = ApiService(client: client, config: config)..token = 'token';
      final auth = AuthService(
        config: config,
        api: api,
        supabaseHttpClient: client,
        sessionStore: MemoryAdminSessionStore(),
      );

      await expectLater(
        auth.signIn('admin@example.com', 'password'),
        throwsA(
          isA<SupabaseAuthException>()
              .having((e) => e.code, 'code', 'auth-not-configured')
              .having(
                (e) => e.message,
                'message',
                contains('SUPABASE_ANON_KEY'),
              ),
        ),
      );
      await expectLater(
        auth.currentUser(),
        throwsA(
          isA<SupabaseAuthException>().having(
            (e) => e.code,
            'code',
            'auth-not-configured',
          ),
        ),
      );
      await expectLater(
        api.get('dashboard/stats'),
        throwsA(
          isA<ApiException>()
              .having((e) => e.statusCode, 'status', 503)
              .having(
                (e) => e.message,
                'message',
                contains('SUPABASE_ANON_KEY'),
              ),
        ),
      );
      expect(requests, 0);
    });

    test('a valid config reaches Supabase Auth with the shared key', () async {
      final config = _resolve(_url, _publishable);
      late http.Request seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response(
          jsonEncode({
            'error': 'invalid_grant',
            'error_description': 'Invalid login credentials',
          }),
          400,
        );
      });
      final auth = AuthService(
        config: config,
        supabaseHttpClient: client,
        sessionStore: MemoryAdminSessionStore(),
      );

      Object? error;
      try {
        await auth.signIn('admin@example.com', 'wrong-password');
      } catch (e) {
        error = e;
      }
      expect(error, isA<SupabaseAuthException>());
      expect(
        (error! as SupabaseAuthException).code,
        isNot('auth-not-configured'),
      );
      expect(seen.url.origin, _url);
      expect(seen.url.path, '/auth/v1/token');
      expect(seen.headers['apikey'] == config.anonKey, isTrue);
    });
  });

  group('startup', () {
    testWidgets('validates config before creating any auth service', (
      tester,
    ) async {
      var created = 0;
      final widget = bootstrapAdminApp(
        config: _resolve(_url, ''),
        createAuthService: (_) {
          created++;
          return FakeAuthService(api: FakeApiService());
        },
      );
      await tester.pumpWidget(widget);

      expect(created, 0);
      expect(find.byKey(const Key('supabase-config-error')), findsOneWidget);
      expect(find.textContaining('SUPABASE_ANON_KEY is empty'), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(
        find.text('Retry'),
        findsNothing,
        reason: 'retrying cannot change compiled defines',
      );
    });

    testWidgets('a valid config creates one auth service, then restores', (
      tester,
    ) async {
      final config = _resolve(_url, _publishable);
      final events = <String>[];
      SupabaseConfig? received;
      late FakeAuthService fake;
      final widget = bootstrapAdminApp(
        config: config,
        createAuthService: (c) {
          events.add('create');
          received = c;
          fake = FakeAuthService(api: FakeApiService());
          return fake;
        },
      );
      events.add('restore:${fake.currentUserCalls}');

      expect(events, ['create', 'restore:1']);
      expect(identical(received, config), isTrue);

      await tester.pumpWidget(widget);
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byKey(const Key('supabase-config-error')), findsNothing);
      expect(find.textContaining('not configured'), findsNothing);
    });
  });
}
