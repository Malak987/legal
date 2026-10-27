import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legal_admin/services/auth_service.dart';
import 'package:legal_admin/services/recovery_callback.dart';

const _url = 'https://qqfzbecwhewswkyxgebu.supabase.co';
const _key = 'sb_publishable_TESTONLY_recovery_000000';
const _redirect = 'https://admin.example.test/';
const _access = 'test-only-access-token';
const _refresh = 'test-only-refresh-token';

class _MemorySessionStore implements AdminSessionStore {
  int writes = 0;
  int clears = 0;
  String? value;

  @override
  Future<String?> readRefreshToken() async => value;

  @override
  Future<void> writeRefreshToken(String token) async {
    writes++;
    value = token;
  }

  @override
  Future<void> clear() async {
    clears++;
    value = null;
  }
}

Uri _callback({
  String? access = _access,
  String? refresh = _refresh,
  String type = 'recovery',
  String expiresIn = '3600',
  String? errorCode,
}) {
  final params = <String, String>{'type': type, 'expires_in': expiresIn};
  if (access != null) params['access_token'] = access;
  if (refresh != null) params['refresh_token'] = refresh;
  if (errorCode != null) params['error_code'] = errorCode;
  return Uri.parse('$_redirect#${Uri(queryParameters: params).query}');
}

AuthService _service({
  required http.Client client,
  required _MemorySessionStore store,
  void Function()? clearCallbackUrl,
}) => AuthService(
  supabaseUrl: _url,
  supabaseAnonKey: _key,
  authRedirectUrl: _redirect,
  supabaseHttpClient: client,
  sessionStore: store,
  clearCallbackUrl: clearCallbackUrl,
);

void main() {
  group('RecoveryCallback parsing', () {
    test('parses a recovery fragment without exposing bearer values', () {
      final parsed = RecoveryCallback.parse(_callback());
      expect(parsed.isAuthCallback, isTrue);
      expect(parsed.isRecovery, isTrue);
      expect(parsed.accessToken, _access);
      expect(parsed.toString(), isNot(contains(_access)));
      expect(parsed.toString(), isNot(contains(_refresh)));
    });

    test('ignores an ordinary route and marks missing/error callbacks', () {
      expect(
        RecoveryCallback.parse(Uri.parse('https://admin.example.test/#/cases'))
            .isAuthCallback,
        isFalse,
      );
      expect(
        RecoveryCallback.parse(_callback(access: null)).isAuthCallback,
        isTrue,
      );
      expect(
        RecoveryCallback.parse(_callback(errorCode: 'otp_expired')).hasError,
        isTrue,
      );
      expect(
        RecoveryCallback.parse(_callback(type: 'signup')).isRecovery,
        isFalse,
      );
    });
  });

  group('Admin recovery session', () {
    test(
      'validates callback, scrubs address bar and keeps tokens memory-only',
      () async {
        final requests = <http.Request>[];
        final store = _MemorySessionStore();
        var scrubCount = 0;
        final service = _service(
          store: store,
          clearCallbackUrl: () => scrubCount++,
          client: MockClient((request) async {
            requests.add(request);
            return http.Response(jsonEncode({'id': 'admin-user'}), 200);
          }),
        );

        final result = await service.restoreRecoveryCallback(_callback());

        expect(result.status, RecoveryCallbackStatus.ready);
        expect(scrubCount, 1);
        expect(requests, hasLength(1));
        expect(requests.single.method, 'GET');
        expect(requests.single.url.path, '/auth/v1/user');
        expect(requests.single.headers['authorization'], 'Bearer $_access');
        expect(store.writes, 0);
        expect(store.clears, 1);
        service.dispose();
      },
    );

    test('rejects expired, missing-token, wrong-origin and error callbacks', () async {
      final store = _MemorySessionStore();
      var requests = 0;
      final service = _service(
        store: store,
        client: MockClient((_) async {
          requests++;
          return http.Response('{}', 200);
        }),
      );

      final expired = await service.restoreRecoveryCallback(
        _callback(expiresIn: '0'),
      );
      expect(expired.status, RecoveryCallbackStatus.invalid);
      final missing = await service.restoreRecoveryCallback(
        _callback(access: null),
      );
      expect(missing.status, RecoveryCallbackStatus.invalid);
      final wrongOrigin = await service.restoreRecoveryCallback(
        Uri.parse(
          'https://attacker.example/#access_token=$_access&type=recovery&expires_in=3600',
        ),
      );
      expect(wrongOrigin.status, RecoveryCallbackStatus.invalid);
      final rejected = await service.restoreRecoveryCallback(
        _callback(errorCode: 'otp_expired'),
      );
      expect(rejected.status, RecoveryCallbackStatus.invalid);
      expect(requests, 0);
      expect(store.writes, 0);
      service.dispose();
    });

    test('Supabase rejects expired callbacks and transient validation failures safely', () async {
      final store = _MemorySessionStore();
      var status = 401;
      final service = _service(
        store: store,
        client: MockClient((_) async => http.Response('{}', status)),
      );

      expect(
        (await service.restoreRecoveryCallback(_callback())).status,
        RecoveryCallbackStatus.invalid,
      );
      status = 503;
      final unavailable = await service.restoreRecoveryCallback(_callback());
      expect(unavailable.status, RecoveryCallbackStatus.unavailable);
      expect(unavailable.message, isNot(contains(_access)));
      expect(store.writes, 0);
      service.dispose();
    });

    test('updates password with recovery access token then clears transient credentials', () async {
      final requests = <http.Request>[];
      final store = _MemorySessionStore();
      final service = _service(
        store: store,
        client: MockClient((request) async {
          requests.add(request);
          return request.method == 'GET'
              ? http.Response(jsonEncode({'id': 'admin-user'}), 200)
              : http.Response(jsonEncode({'id': 'admin-user'}), 200);
        }),
      );

      expect(
        (await service.restoreRecoveryCallback(_callback())).status,
        RecoveryCallbackStatus.ready,
      );
      await service.updatePasswordFromRecovery('a-new-test-password');

      expect(requests.map((r) => r.method), ['GET', 'PUT']);
      expect(requests.last.url.path, '/auth/v1/user');
      expect(requests.last.headers['authorization'], 'Bearer $_access');
      expect(jsonDecode(requests.last.body), {
        'password': 'a-new-test-password',
      });
      expect(store.writes, 0);
      expect(store.clears, 2);
      service.dispose();
    });

    test(
      'invalid update links are rejected; server failures remain retryable',
      () async {
        final store = _MemorySessionStore();
        var putStatus = 500;
        final service = _service(
          store: store,
          client: MockClient((request) async {
            if (request.method == 'GET') {
              return http.Response('{"id":"admin-user"}', 200);
            }
            return http.Response('{}', putStatus);
          }),
        );
        await service.restoreRecoveryCallback(_callback());
        await expectLater(
          service.updatePasswordFromRecovery('a-new-test-password'),
          throwsA(
            isA<SupabaseAuthException>().having(
              (e) => e.code,
              'code',
              'recovery-update-failed',
            ),
          ),
        );
        putStatus = 401;
        await expectLater(
          service.updatePasswordFromRecovery('a-new-test-password'),
          throwsA(
            isA<SupabaseAuthException>().having(
              (e) => e.code,
              'code',
              'recovery-link-invalid',
            ),
          ),
        );
        service.dispose();
      },
    );
  });
}
