import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legalserviceapp/services/api_client.dart';
import 'package:legalserviceapp/services/auth_service.dart';
import 'package:legalserviceapp/state/session_controller.dart';
import 'package:legalserviceapp/state/start_route.dart';

import 'support/fakes.dart';

/// Lets queued microtasks (and the stream listeners) run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('AuthService.register', () {
    test('creates a client account then reads its server-owned profile', () async {
      final gateway = FakeAuthGateway();
      final calls = <String>[];
      final api = testApiClient(uid: 'uid-new', handler: (request, _) async {
        calls.add('${request.method} ${request.url.path}');
        return jsonOk(profileJson(id: 'uid-new', name: 'Sara'));
      });
      final auth = AuthService(gateway: gateway, api: api);

      final profile = await auth.register(
        name: 'Sara',
        email: 'sara@example.com',
        password: 'secret123',
      );

      expect(profile.name, 'Sara');
      expect(calls, ['GET /rest/v1/users']);
      expect(gateway.createAccountCalls, 1);
    });

    test('rejects a non-client role from the authoritative profile', () async {
      final gateway = FakeAuthGateway();
      final api = testApiClient(
        uid: 'uid-new',
        handler: (_, __) async =>
            jsonOk(profileJson(id: 'uid-new', role: 'lawyer')),
      );
      final auth = AuthService(gateway: gateway, api: api);

      await expectLater(
        auth.register(
          name: 'Sara',
          email: 'sara@example.com',
          password: 'secret123',
        ),
        throwsA(isA<AuthException>()
            .having((e) => e.accountCreated, 'accountCreated', isTrue)),
      );
      expect(gateway.currentUser, isNull,
          reason: 'the client app must close non-client sessions');
      expect(gateway.signOutCalls, 1);
    });

    test('profile failure preserves the created account for retry', () async {
      final gateway = FakeAuthGateway();
      final api = testApiClient(
        uid: 'uid-new',
        handler: (_, __) async => jsonError(500, 'Profile service unavailable'),
      );
      final auth = AuthService(gateway: gateway, api: api);

      await expectLater(
        auth.register(name: 'Sara', email: 'sara@example.com', password: 'secret123'),
        throwsA(isA<AuthException>()
            .having((e) => e.accountCreated, 'accountCreated', isTrue)),
      );
      expect(gateway.currentUser, isNotNull);
    });

    test('confirmed-email registration never provisions through Express', () async {
      final gateway = FakeAuthGateway()
        ..createAccountError = AuthException(
          'Check your email to confirm it.',
          code: 'email-confirmation-required',
          accountCreated: true,
        );
      var apiCalls = 0;
      final api = testApiClient(handler: (_, __) async {
        apiCalls++;
        return jsonOk(profileJson());
      });

      await expectLater(
        AuthService(gateway: gateway, api: api).register(
          name: 'Sara', email: 'sara@example.com', password: 'secret123'),
        throwsA(isA<AuthException>().having(
          (e) => e.accountCreated, 'accountCreated', isTrue)),
      );
      expect(apiCalls, 0);
      expect(gateway.currentUser, isNull);
    });
  });

  group('AuthService.loadProfile', () {
    test('reads an existing server-owned profile without writing', () async {
      final gateway = FakeAuthGateway(
        initialUser: const AuthUser(uid: 'uid-1', email: 'sara@example.com'),
      );
      var posts = 0;
      final api = testApiClient(handler: (request, _) async {
        if (request.method == 'POST') posts++;
        return jsonOk(profileJson());
      });

      final profile = await AuthService(gateway: gateway, api: api).loadProfile();
      expect(profile.uid, 'uid-1');
      expect(posts, 0);
    });

    test('does not create a missing profile from the client', () async {
      final gateway = FakeAuthGateway(
        initialUser: const AuthUser(uid: 'uid-1', email: 'sara@example.com'),
      );
      var posts = 0;
      final api = testApiClient(handler: (request, _) async {
        if (request.method == 'POST') posts++;
        return jsonError(404, 'No profile is linked to this Auth account yet.');
      });

      await expectLater(
        AuthService(gateway: gateway, api: api).loadProfile(),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', 'profile-not-found')),
      );
      expect(posts, 0);
      expect(gateway.currentUser, isNull,
          reason: 'missing profiles are denied and the session is cleared');
      expect(gateway.signOutCalls, 1);
    });

    test('rejects missing or unknown profile roles and clears the session', () async {
      for (final role in ['', 'owner', 'CLIENT', 'unknown']) {
        final gateway = FakeAuthGateway(
          initialUser: const AuthUser(uid: 'uid-1', email: 'sara@example.com'),
        );
        final api = testApiClient(
          handler: (_, __) async =>
              jsonOk(profileJson(role: role)),
        );

        await expectLater(
          AuthService(gateway: gateway, api: api).loadProfile(),
          throwsA(isA<AuthException>()
              .having((e) => e.code, 'code', 'role-not-authorized')),
        );
        expect(gateway.currentUser, isNull, reason: 'role=$role');
        expect(gateway.signOutCalls, 1, reason: 'role=$role');
      }
    });

    test('refuses to load a profile without a session', () async {
      final api = testApiClient(handler: (_, __) async => jsonOk(profileJson()));
      await expectLater(
        AuthService(gateway: FakeAuthGateway(), api: api).loadProfile(),
        throwsA(isA<AuthException>()),
      );
    });
  });

  group('SessionController', () {
    late FakeAuthGateway gateway;
    late ApiClient api;

    SessionController build({
      http.Response Function(String method)? responder,
    }) {
      gateway = FakeAuthGateway();
      api = testApiClient(handler: (request, _) async {
        if (responder != null) return responder(request.method);
        return jsonOk(profileJson(name: 'Sara'));
      });
      return SessionController(
        auth: AuthService(gateway: gateway, api: api),
      );
    }

    test('starts out resolving so no screen can claim a session', () {
      final session = build();
      expect(session.status, SessionStatus.resolving);
      expect(session.isSignedIn, isFalse);
      session.dispose();
    });

    test('sign-in loads the profile before reporting success', () async {
      final session = build();
      final ok = await session.signIn(
        email: 'sara@example.com',
        password: 'secret123',
      );
      await settle();

      expect(ok, isTrue);
      expect(session.status, SessionStatus.signedIn);
      expect(session.profile?.name, 'Sara');
      expect(session.error, isNull);
      session.dispose();
    });

    test('a bad password leaves the app signed out with a message', () async {
      final session = build();
      gateway.signInError =
          AuthException('Incorrect email or password.', code: 'wrong-password');

      final ok = await session.signIn(
        email: 'sara@example.com',
        password: 'nope',
      );
      await settle();

      expect(ok, isFalse);
      expect(session.status, SessionStatus.signedOut);
      expect(session.profile, isNull);
      expect(session.error, 'Incorrect email or password.');
      session.dispose();
    });

    test('a profile read failure keeps protected screens closed', () async {
      final session = build(
        responder: (_) => jsonError(500, 'Server exploded'),
      );

      final ok = await session.signIn(
        email: 'sara@example.com',
        password: 'secret123',
      );
      await settle();

      expect(ok, isFalse);
      expect(session.isSignedIn, isFalse);
      expect(session.status, SessionStatus.profileUnavailable);
      expect(session.error, contains('Could not reach the server'));
      session.dispose();
    });

    test('registration failure does not look like a session', () async {
      final session = build(
        responder: (_) => jsonError(500, 'Server exploded'),
      );

      final ok = await session.register(
        name: 'Sara',
        email: 'sara@example.com',
        password: 'secret123',
      );
      await settle();

      expect(ok, isFalse);
      expect(session.status, SessionStatus.profileUnavailable);
      expect(gateway.currentUser, isNotNull,
          reason: 'the Auth account is preserved for email confirmation/retry');
      session.dispose();
    });

    test('a sign-in superseded by a sign-out never reports success', () async {
      final session = build();
      // The gateway is signed out while the sign-in is still in flight; the
      // stream does not announce the intermediate account (the event would be
      // stale by the time it arrived).
      gateway.emitAuthEvents = false;

      final pending = session.signIn(
        email: 'sara@example.com',
        password: 'secret123',
      );
      await session.signOut();

      expect(await pending, isFalse, reason: 'the session is gone');
      expect(session.status, SessionStatus.signedOut);
      expect(session.isSignedIn, isFalse);
      session.dispose();
    });

    test('a profile update that returns a non-client role closes the session', () async {
      final session = build(
        responder: (method) => method == 'PATCH'
            ? supabaseOk([profileJson(role: 'lawyer', name: 'Sara')])
            : supabaseOk([profileJson(role: 'client')]),
      );
      await session.signIn(email: 'sara@example.com', password: 'secret123');
      await settle();
      expect(session.profile?.role, 'client');

      await expectLater(
        session.updateProfile(name: 'Sara', email: 'sara@example.com'),
        throwsA(isA<AuthException>()
            .having((e) => e.code, 'code', 'role-not-authorized')),
      );

      expect(session.status, SessionStatus.signedOut);
      expect(session.profile, isNull);
      expect(gateway.signOutCalls, 1);
      session.dispose();
    });

    test('a failed profile refresh recovers on retry', () async {
      var calls = 0;
      final session = build(
        responder: (_) {
          calls++;
          return calls == 1
              ? jsonError(500, 'Server exploded')
              : jsonOk(profileJson(name: 'Sara'));
        },
      );
      // Keep the stream quiet so the only retry is the explicit one below.
      gateway.emitAuthEvents = false;

      final ok = await session.signIn(
        email: 'sara@example.com',
        password: 'secret123',
      );
      await settle();
      expect(ok, isFalse);
      expect(session.status, SessionStatus.profileUnavailable);

      await session.refreshProfile();
      await settle();

      expect(session.status, SessionStatus.signedIn);
      expect(session.profile?.name, 'Sara');
      session.dispose();
    });

    test('sign-out clears the profile and the user', () async {
      final session = build();
      await session.signIn(email: 'sara@example.com', password: 'secret123');
      await settle();

      await session.signOut();
      await settle();

      expect(session.status, SessionStatus.signedOut);
      expect(session.user, isNull);
      expect(session.profile, isNull);
      expect(gateway.signOutCalls, 1);
      session.dispose();
    });

    /// Counts profile reads so "one listener, one fetch" is asserted on
    /// behaviour (requests made) rather than on internal fields.
    SessionController buildCounting(void Function() onRead) {
      gateway = FakeAuthGateway();
      api = testApiClient(handler: (_, __) async {
        onRead();
        return jsonOk(profileJson());
      });
      return SessionController(
        auth: AuthService(gateway: gateway, api: api),
      );
    }

    test('a restored Supabase session loads the profile exactly once',
        () async {
      var reads = 0;
      final session = buildCounting(() => reads++);
      session.start();
      gateway.emit(const AuthUser(uid: 'uid-1', email: 'sara@example.com'));
      await settle();
      await settle();

      expect(session.status, SessionStatus.signedIn);
      expect(session.profile?.uid, 'uid-1');
      expect(reads, 1);

      // The same account reported again (a token refresh, say) must not
      // trigger another profile read.
      gateway.emit(const AuthUser(uid: 'uid-1', email: 'sara@example.com'));
      await settle();
      expect(session.status, SessionStatus.signedIn);
      expect(reads, 1);
      session.dispose();
    });

    test('starting twice still yields a single subscription', () async {
      var reads = 0;
      final session = buildCounting(() => reads++);
      session.start();
      session.start();
      gateway.emit(const AuthUser(uid: 'uid-1', email: 'sara@example.com'));
      await settle();
      await settle();

      expect(session.status, SessionStatus.signedIn);
      expect(reads, 1, reason: 'a second listener would double every read');
      session.dispose();
    });

    test('a late profile read cannot resurrect a signed-out session',
        () async {
      final session = build();
      session.start();
      session.start();
      final pending = session.refreshProfile();
      await session.signOut();
      await pending;
      await settle();

      expect(session.status, SessionStatus.signedOut);
      expect(session.profile, isNull);
      session.dispose();
    });
  });

  group('SessionController.changePassword', () {
    late FakeAuthGateway gateway;
    late ApiClient api;

    SessionController build() {
      gateway = FakeAuthGateway();
      api = testApiClient(handler: (_, __) async => jsonOk(profileJson()));
      return SessionController(auth: AuthService(gateway: gateway, api: api));
    }

    test('changes the password without ending the session', () async {
      final session = build();
      await session.signIn(email: 'sara@example.com', password: 'secret123');
      await settle();

      await session.changePassword(
        currentPassword: 'secret123',
        newPassword: 'n3wSecret!',
      );

      expect(gateway.changePasswordCalls, 1);
      expect(gateway.lastCurrentPassword, 'secret123');
      expect(gateway.lastNewPassword, 'n3wSecret!');
      // The user keeps working: a password change must not sign them out.
      expect(session.status, SessionStatus.signedIn);
      expect(gateway.signOutCalls, 0);
      session.dispose();
    });

    test('surfaces the reason a password change was refused', () async {
      final session = build();
      await session.signIn(email: 'sara@example.com', password: 'secret123');
      await settle();
      gateway.changePasswordError = AuthException(
        'Please sign in again to finish this action.',
        code: 'requires-recent-login',
      );

      await expectLater(
        session.changePassword(
          currentPassword: 'wrong',
          newPassword: 'n3wSecret!',
        ),
        throwsA(isA<AuthException>().having(
          (e) => e.message,
          'message',
          'Please sign in again to finish this action.',
        )),
      );

      // A failed change leaves the session exactly as it was.
      expect(session.status, SessionStatus.signedIn);
      expect(session.profile?.name, 'Sara Ali');
      session.dispose();
    });

    test('refuses to change a password with no signed-in account', () async {
      final session = build();

      await expectLater(
        session.changePassword(
          currentPassword: 'secret123',
          newPassword: 'n3wSecret!',
        ),
        throwsA(isA<AuthException>()),
      );

      // Nothing was sent: the gateway is only reached for a real session.
      expect(gateway.changePasswordCalls, 0);
      session.dispose();
    });
  });

  group('routing gate', () {
    test('only a loaded profile reaches the protected home', () {
      expect(startScreenFor(SessionStatus.signedIn), StartScreen.home);
      expect(startScreenFor(SessionStatus.signedOut), StartScreen.onboarding);
      expect(
        startScreenFor(SessionStatus.resolving),
        StartScreen.onboarding,
      );
      expect(
        startScreenFor(SessionStatus.profileUnavailable),
        StartScreen.onboarding,
      );
    });
  });

  group('Supabase profile transport', () {
    const authUid = '00000000-0000-4000-8000-000000000099';
    const legacyUid = 'legacy-client-001';
    const profileRow = <String, dynamic>{
      'id': legacyUid,
      'uid': legacyUid,
      'name': 'Sara Ali',
      'email': 'sara@example.com',
      'role': 'client',
      'phone': '',
      'address': '',
      'avatar': '',
    };

    test('loads the RLS-scoped application profile without an Express request', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode(<dynamic>[profileRow]), 200);
      });
      final api = ApiClient(
        client: client,
        idTokenProvider: () async => 'supabase-access-token',
        currentUidProvider: () => authUid,
        supabaseUrl: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        supabaseAnonKey: 'public-anon-key',
      );

      final profile = await api.getMyProfile();
      expect(profile.uid, legacyUid);
      expect(api.currentUid, legacyUid);
      expect(requests.single.url.path, '/rest/v1/users');
      expect(
        requests.single.url.queryParameters['or'],
        '(id.eq.$authUid,auth_user_id.eq.$authUid)',
      );
      expect(requests.single.headers['apikey'], 'public-anon-key');
      expect(requests.single.headers['Authorization'], 'Bearer supabase-access-token');
      expect(requests.single.url.host, 'qqfzbecwhewswkyxgebu.supabase.co');
      api.dispose();
    });

    test('patches only RLS-approved profile fields and blocks email changes', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.method == 'GET') {
          return http.Response(jsonEncode(<dynamic>[profileRow]), 200);
        }
        return http.Response(
          jsonEncode(<dynamic>[
            <String, dynamic>{...profileRow, 'name': 'Sara Updated', 'phone': '123'},
          ]),
          200,
        );
      });
      final api = ApiClient(
        client: client,
        idTokenProvider: () async => 'supabase-access-token',
        currentUidProvider: () => authUid,
        supabaseUrl: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        supabaseAnonKey: 'public-anon-key',
      );

      final updated = await api.updateMyProfile(
        name: 'Sara Updated',
        email: 'sara@example.com',
        phone: '123',
      );
      expect(updated.name, 'Sara Updated');
      expect(requests.map((request) => request.method), ['GET', 'PATCH']);
      expect(requests.last.url.queryParameters['id'], 'eq.$legacyUid');
      final patch = jsonDecode(requests.last.body) as Map<String, dynamic>;
      expect(patch, {'name': 'Sara Updated', 'phone': '123'});
      expect(patch.containsKey('email'), isFalse);
      expect(patch.containsKey('role'), isFalse);

      await expectLater(
        api.updateMyProfile(name: 'Sara', email: 'new@example.com'),
        throwsA(isA<ApiException>().having((error) => error.statusCode, 'status', 403)),
      );
      expect(requests.length, 2, reason: 'email change must not reach PostgREST');
      api.dispose();
    });
  });

  group('SupabaseAuthGateway', () {
    test('public client registration is disabled by default', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        return http.Response('{}', 200);
      });
      final gateway = SupabaseAuthGateway(
        client: client,
        supabaseUrl: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        supabaseAnonKey: 'public-anon-key',
        sessionStore: MemoryAuthSessionStore(),
      );

      await expectLater(
        gateway.createAccount(
          email: 'sara@example.com',
          password: 'secret123',
        ),
        throwsA(isA<AuthException>()
            .having((error) => error.code, 'code', 'signup-not-enabled')),
      );
      expect(requests, isEmpty);
      gateway.dispose();
    });

    test('signs in, refreshes tokens, changes password, and signs out via Supabase Auth REST API', () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        requests.add('${request.method} ${request.url.path}?${request.url.query}');
        if (request.url.path.endsWith('/auth/v1/token') &&
            request.url.queryParameters['grant_type'] == 'password') {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          if (body['password'] == 'wrong') {
            return http.Response(
              jsonEncode(<String, dynamic>{
                'error_code': 'invalid_credentials',
                'msg': 'Invalid login credentials',
              }),
              400,
            );
          }
          return http.Response(
            jsonEncode(<String, dynamic>{
              'access_token': 'supa-access-jwt',
              'refresh_token': 'supa-refresh-jwt',
              'user': <String, dynamic>{
                'id': '00000000-0000-4000-8000-000000000099',
                'email': body['email'],
                'user_metadata': <String, dynamic>{'legacy_uid': 'spoofed-legacy-id'},
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/auth/v1/user') &&
            request.method == 'PUT') {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'id': '00000000-0000-4000-8000-000000000099',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/auth/v1/logout')) {
          return http.Response('', 204);
        }
        return http.Response('{}', 404);
      });

      final gateway = SupabaseAuthGateway(
        client: client,
        supabaseUrl: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        supabaseAnonKey: 'public-anon-key',
        sessionStore: MemoryAuthSessionStore(),
      );

      final user = await gateway.signIn(
        email: 'sara@example.com',
        password: 'secret123',
      );
      expect(user.uid, '00000000-0000-4000-8000-000000000099');
      expect(user.email, 'sara@example.com');
      expect(await gateway.getAccessToken(), 'supa-access-jwt');

      await expectLater(
        gateway.changePassword(
          currentPassword: 'wrong',
          newPassword: 'n3wPassword!',
        ),
        throwsA(isA<AuthException>().having(
          (e) => e.code,
          'code',
          'invalid-credential',
        )),
      );

      await gateway.changePassword(
        currentPassword: 'secret123',
        newPassword: 'n3wPassword!',
      );

      await gateway.signOut();
      expect(gateway.currentUser, isNull);
      expect(await gateway.getAccessToken(), isNull);
    });

    test('restores the encrypted refresh-token session and persists rotation', () async {
      const authUid = '00000000-0000-4000-8000-000000000099';
      final store = MemoryAuthSessionStore()..refreshToken = 'stored-refresh';
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/auth/v1/token')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['refresh_token'], 'stored-refresh');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'access_token': 'restored-access',
              'refresh_token': 'rotated-refresh',
              'expires_in': 3600,
              'user': <String, dynamic>{'id': authUid, 'email': 'sara@example.com'},
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final gateway = SupabaseAuthGateway(
        client: client,
        supabaseUrl: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        supabaseAnonKey: 'public-anon-key',
        sessionStore: store,
      );

      final user = await gateway.restoreSession();
      expect(user?.uid, authUid);
      expect(gateway.currentUser?.email, 'sara@example.com');
      expect(await gateway.getAccessToken(), 'restored-access');
      expect(store.refreshToken, 'rotated-refresh');
      expect(requests.single.url.queryParameters['grant_type'], 'refresh_token');
      gateway.dispose();
    });

    test('password reset uses the explicitly allow-listed redirect', () async {
      http.Request? seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response('', 200);
      });
      final gateway = SupabaseAuthGateway(
        client: client,
        supabaseUrl: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        supabaseAnonKey: 'public-anon-key',
        authRedirectUrl: 'https://legal.example/auth/callback',
        sessionStore: MemoryAuthSessionStore(),
      );

      await gateway.requestPasswordReset(email: 'sara@example.com');
      expect(seen?.url.path, '/auth/v1/recover');
      expect(seen?.url.queryParameters['redirect_to'],
          'https://legal.example/auth/callback');
      expect(jsonDecode(seen!.body), <String, dynamic>{'email': 'sara@example.com'});
      gateway.dispose();
    });

    test('recovery callback authorizes setting a new password', () async {
      const authUid = '00000000-0000-4000-8000-000000000099';
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/auth/v1/user') && request.method == 'GET') {
          expect(request.headers['Authorization'], 'Bearer recovery-access');
          return http.Response(
            jsonEncode(<String, dynamic>{'id': authUid, 'email': 'sara@example.com'}),
            200,
          );
        }
        if (request.url.path.endsWith('/auth/v1/user') && request.method == 'PUT') {
          expect(jsonDecode(request.body), <String, dynamic>{'password': 'newPassword123'});
          return http.Response('{}', 200);
        }
        return http.Response('', 204);
      });
      final gateway = SupabaseAuthGateway(
        client: client,
        supabaseUrl: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        supabaseAnonKey: 'public-anon-key',
        sessionStore: MemoryAuthSessionStore(),
      );

      final user = await gateway.restoreSession(
        callbackUri: Uri.parse(
          'https://legal.example/auth/callback#access_token=recovery-access&refresh_token=recovery-refresh&type=recovery',
        ),
      );
      expect(user?.uid, authUid);
      expect(gateway.isPasswordRecovery, isTrue);
      await gateway.setPasswordFromRecovery('newPassword123');
      expect(gateway.isPasswordRecovery, isFalse);
      expect(requests.map((request) => request.method), ['GET', 'PUT']);
      gateway.dispose();
    });

    test('signup confirmation-required state keeps the account and skips Express', () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/auth/v1/signup')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'user': <String, dynamic>{
                'id': '00000000-0000-4000-8000-000000000099',
                'email': 'sara@example.com',
              },
            }),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final gateway = SupabaseAuthGateway(
        client: client,
        supabaseUrl: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        supabaseAnonKey: 'public-anon-key',
        authRedirectUrl: 'https://legal.example/auth/callback',
        allowClientSignup: true,
        sessionStore: MemoryAuthSessionStore(),
      );
      final api = ApiClient(
        client: client,
        idTokenProvider: () => gateway.getAccessToken(),
        currentUidProvider: () => gateway.currentUser?.uid,
        supabaseUrl: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        supabaseAnonKey: 'public-anon-key',
      );

      await expectLater(
        AuthService(gateway: gateway, api: api).register(
          name: 'Sara Ali',
          email: 'sara@example.com',
          password: 'secret123',
        ),
        throwsA(isA<AuthException>()
            .having((error) => error.code, 'code', 'email-confirmation-required')
            .having((error) => error.accountCreated, 'accountCreated', isTrue)),
      );
      final signup = jsonDecode(requests.single.body) as Map<String, dynamic>;
      expect((signup['data'] as Map<String, dynamic>)['name'], 'Sara Ali');
      expect(requests.map((request) => request.url.path), ['/auth/v1/signup']);
      expect(gateway.currentUser, isNull);
      expect(api.token, isNull);
      api.dispose();
    });

    test('confirmed signup reads the trigger-created profile from PostgREST only', () async {
      const authUid = '00000000-0000-4000-8000-000000000099';
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (request.url.path.endsWith('/auth/v1/signup')) {
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          final metadata = body['data'] as Map<String, dynamic>;
          expect(metadata['name'], 'Sara Ali');
          expect(metadata.containsKey('role'), isFalse,
              reason: 'public clients never supply an authorization role');
          return http.Response(
            jsonEncode(<String, dynamic>{
              'access_token': 'supa-access-jwt',
              'refresh_token': 'supa-refresh-jwt',
              'user': <String, dynamic>{'id': authUid, 'email': 'sara@example.com'},
            }),
            200,
          );
        }
        if (request.url.path == '/rest/v1/users') {
          expect(request.headers['Authorization'], 'Bearer supa-access-jwt');
          return http.Response(
            jsonEncode(<dynamic>[
              <String, dynamic>{
                'id': authUid,
                'uid': authUid,
                'name': 'Sara Ali',
                'email': 'sara@example.com',
                'role': 'client',
              },
            ]),
            200,
          );
        }
        return http.Response('{}', 404);
      });
      final gateway = SupabaseAuthGateway(
        client: client,
        supabaseUrl: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        supabaseAnonKey: 'public-anon-key',
        authRedirectUrl: 'https://legal.example/auth/callback',
        allowClientSignup: true,
        sessionStore: MemoryAuthSessionStore(),
      );
      final api = ApiClient(
        client: client,
        idTokenProvider: () => gateway.getAccessToken(),
        forceRefreshTokenProvider: () => gateway.getAccessToken(forceRefresh: true),
        currentUidProvider: () => gateway.currentUser?.uid,
        supabaseUrl: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        supabaseAnonKey: 'public-anon-key',
      );

      final profile = await AuthService(gateway: gateway, api: api).register(
        name: 'Sara Ali',
        email: 'sara@example.com',
        password: 'secret123',
      );
      expect(profile.uid, authUid);
      expect(profile.role, 'client');
      expect(requests.map((request) => request.url.path), [
        '/auth/v1/signup',
        '/rest/v1/users',
      ]);
      api.dispose();
    });
  });
}
