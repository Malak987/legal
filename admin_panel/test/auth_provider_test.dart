// Unit tests for AuthProvider: sign-in outcomes, session restoration, and the
// guards that prevent the login -> logout -> login redirect loop.
//
// These are pure Dart — no widgets — and use FakeAuthService / FakeApiService
// from test/fakes.dart, so they need no Firebase project and no network.

import 'dart:async';
import 'dart:convert';

// `firebase_auth` re-exports a platform-level `AuthProvider`, which collides
// with the admin panel's own AuthProvider class and made every `AuthProvider(`
// call below ambiguous. Only `User` is needed from here, so the colliding name
// is hidden rather than the whole import dropped.
import 'package:firebase_auth/firebase_auth.dart' hide AuthProvider;
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legal_admin/providers/auth_provider.dart';
import 'package:legal_admin/services/api_service.dart';
import 'package:legal_admin/services/auth_service.dart';

import 'fakes.dart';

void main() {
  group('AuthProvider.signIn', () {
    test('successful admin sign-in authenticates and clears loading', () async {
      final api = FakeApiService();
      final service = FakeAuthService(api: api, session: adminSession());
      final provider = AuthProvider(service);

      final ok = await provider.signIn('admin@legalapp.com', 'pw');

      expect(ok, isTrue);
      expect(provider.status, AuthStatus.authenticated);
      expect(provider.isAuthenticated, isTrue);
      expect(provider.isLoading, isFalse);
      expect(provider.error, isNull);
      expect(provider.session?.role, 'admin');
      expect(service.lastEmail, 'admin@legalapp.com');
    });

    test('invalid credentials surface a readable error and leave loading',
        () async {
      final api = FakeApiService();
      final service = FakeAuthService(
        api: api,
        signInError: Exception('[firebase_auth/invalid-credential] nope'),
      );
      final provider = AuthProvider(service);

      final ok = await provider.signIn('admin@legalapp.com', 'wrong');

      expect(ok, isFalse);
      expect(provider.status, AuthStatus.unauthenticated);
      expect(provider.session, isNull);
      expect(provider.error, 'Incorrect email or password.');
      // Must not remain stuck in a loading state after a failure.
      expect(provider.isLoading, isFalse);
    });

    test('a rejected non-admin account never becomes authenticated', () async {
      final api = FakeApiService();
      final service = FakeAuthService(
        api: api,
        signInError: NotAdminException('client'),
      );
      final provider = AuthProvider(service);

      final ok = await provider.signIn('client@example.com', 'pw');

      expect(ok, isFalse);
      expect(provider.status, AuthStatus.unauthenticated);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.session, isNull);
      expect(provider.error, contains('not an administrator'));
    });

    test('unknown user error is humanised', () async {
      final provider = AuthProvider(
        FakeAuthService(
          api: FakeApiService(),
          signInError: Exception('[firebase_auth/user-not-found] missing'),
        ),
      );

      await provider.signIn('nobody@example.com', 'pw');

      expect(provider.error, 'No account found with this email.');
      expect(provider.isLoading, isFalse);
    });
  });

  // ------------------------------------------------------------------
  //  Redirect-loop regressions
  // ------------------------------------------------------------------

  group('AuthProvider state guards', () {
    test('a late restore() cannot overwrite a newer successful signIn()',
        () async {
      // The exact race behind the redirect loop: restore() starts a slow
      // Firestore read, the user signs in, then the stale restore lands and
      // must NOT reset the status back to unauthenticated.
      final gate = Completer<AdminSession?>();
      final service = FakeAuthService(
        api: FakeApiService(),
        restoredSession: null,
        currentUserGate: gate,
        session: adminSession(),
      );
      final provider = AuthProvider(service);

      final restoreFuture = provider.restore();
      await Future<void>.delayed(Duration.zero);

      final ok = await provider.signIn('admin@legalapp.com', 'pw');
      expect(ok, isTrue, reason: 'signIn must not be blocked by restore()');
      expect(provider.status, AuthStatus.authenticated);

      gate.complete(null); // the stale restore finally resolves
      await restoreFuture;
      await Future<void>.delayed(Duration.zero);

      expect(
        provider.status,
        AuthStatus.authenticated,
        reason: 'a stale restore must never clobber a newer sign-in',
      );
      expect(provider.session?.role, 'admin');
    });

    test('a transient profile read failure never signs the user out', () async {
      final service = FakeAuthService(
        api: FakeApiService(),
        currentUserError: ProfileReadException(
          'Could not read your admin profile from the server (unavailable). '
          'Check your connection and your Firestore security rules, then retry.',
        ),
      );
      final provider = AuthProvider(service);

      await provider.restore();

      // Not bounced to the login screen, and the session is preserved.
      expect(provider.status, AuthStatus.unknown);
      expect(provider.error, contains('Could not read your admin profile'));
      expect(provider.error, contains('Firestore security rules'));
      expect(
        service.signOutCalls,
        0,
        reason: 'a transient failure must never destroy a valid session',
      );
    });

    test('retry() recovers once the transient failure clears', () async {
      final service = FakeAuthService(
        api: FakeApiService(),
        currentUserError: ProfileReadException('offline'),
      );
      final provider = AuthProvider(service);

      await provider.restore();
      expect(provider.status, AuthStatus.unknown);

      service.currentUserError = null;
      service.restoredSession = adminSession();
      await provider.retry();

      expect(provider.status, AuthStatus.authenticated);
      expect(provider.error, isNull);
    });

    test('restore() is a no-op once an admin session is held', () async {
      final service = FakeAuthService(
        api: FakeApiService(),
        restoredSession: adminSession(),
      );
      final provider = AuthProvider(service);

      await provider.restore();
      final callsBefore = service.currentUserCalls;

      await provider.restore();
      await provider.restore();

      expect(service.currentUserCalls, callsBefore);
      expect(provider.status, AuthStatus.authenticated);
    });

    test('signIn() ignores a double submit', () async {
      final completer = Completer<AdminSession>();
      final service = _GatedSignInService(completer);
      final provider = AuthProvider(service);

      final first = provider.signIn('a@b.c', 'pw');
      await Future<void>.delayed(Duration.zero);
      final second = provider.signIn('a@b.c', 'pw');

      completer.complete(adminSession());
      await first;
      final secondResult = await second;

      expect(secondResult, isFalse);
      expect(service.signInCalls, 1);
    });
  });

  group('AuthProvider auth-state listener', () {
    test('is created only once, so restoration cannot be repeated', () async {
      final service = FakeAuthService(
        api: FakeApiService(),
        restoredSession: null,
      );
      final provider = AuthProvider(service);

      provider.bindAuthState();
      provider.bindAuthState();
      provider.bindAuthState();

      service.emitAuthState(null);
      await Future<void>.delayed(Duration.zero);

      // A single listener signs out once; it does not restart restoration.
      expect(service.currentUserCalls, 0);
      expect(provider.status, AuthStatus.unauthenticated);
      expect(provider.error, contains('session has ended'));

      provider.dispose();
    });

    test('a server-side sign-out clears the admin session', () async {
      final service = FakeAuthService(
        api: FakeApiService(),
        restoredSession: adminSession(),
      );
      final provider = AuthProvider(service);
      await provider.restore();
      expect(provider.status, AuthStatus.authenticated);

      provider.bindAuthState();
      service.emitAuthState(null);
      await Future<void>.delayed(Duration.zero);

      expect(provider.status, AuthStatus.unauthenticated);
      expect(provider.session, isNull);
      expect(provider.isAuthenticated, isFalse);

      provider.dispose();
    });
  });

  group('AuthProvider.restore', () {
    test('restores an existing admin session', () async {
      final api = FakeApiService();
      final provider = AuthProvider(
        FakeAuthService(api: api, restoredSession: adminSession()),
      );

      await provider.restore();

      expect(provider.status, AuthStatus.authenticated);
      expect(provider.session?.role, 'admin');
      expect(provider.isLoading, isFalse);
    });

    test('no persisted session results in unauthenticated', () async {
      final provider = AuthProvider(
        FakeAuthService(api: FakeApiService(), restoredSession: null),
      );

      await provider.restore();

      expect(provider.status, AuthStatus.unauthenticated);
      expect(provider.session, isNull);
    });

    test('a missing profile is reported with an actionable message', () async {
      final provider = AuthProvider(
        FakeAuthService(
          api: FakeApiService(),
          currentUserError: AdminProfileMissingException('admin-uid'),
        ),
      );

      await provider.restore();

      expect(provider.status, AuthStatus.unauthenticated);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.error, contains('No user profile found'));
      expect(provider.error, contains('users/admin-uid'));
    });

    test('a restored non-admin is rejected', () async {
      final provider = AuthProvider(
        FakeAuthService(
          api: FakeApiService(),
          currentUserError: NotAdminException('client'),
        ),
      );

      await provider.restore();

      expect(provider.status, AuthStatus.unauthenticated);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.session, isNull);
      expect(provider.error, contains('not an administrator'));
    });
  });

  group('AuthProvider.signOut', () {
    test('clears the session and reports unauthenticated', () async {
      final service = FakeAuthService(
        api: FakeApiService(),
        restoredSession: adminSession(),
      );
      final provider = AuthProvider(service);
      await provider.restore();
      expect(provider.status, AuthStatus.authenticated);

      await provider.signOut();

      expect(provider.status, AuthStatus.unauthenticated);
      expect(provider.session, isNull);
      expect(provider.error, isNull);
      expect(service.signOutCalls, 1);
    });
  });

  group('ApiService token handling', () {
    test('uses a fresh token from the provider when available', () async {
      final api = FakeApiService();
      api.token = 'stale-token';
      api.tokenProvider = () async => 'fresh-token';

      await api.get('users');

      expect(api.lastAuthHeader, 'Bearer fresh-token');
    });

    test('falls back to the stored token when no provider is set', () async {
      final api = FakeApiService();
      api.token = 'stored-token';

      await api.get('users');

      expect(api.lastAuthHeader, 'Bearer stored-token');
    });

    test('sends no Authorization header when there is no token', () async {
      final api = FakeApiService();

      await api.get('users');

      expect(api.lastAuthHeader, isNull);
    });
  });

  group('AuthService (Supabase mode)', () {
    test('authenticates an admin via Supabase Auth and verifies role via PostgREST', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/auth/v1/token')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'access_token': 'supa-admin-jwt',
              'user': <String, dynamic>{
                'id': '00000000-0000-4000-8000-000000000001',
                'email': 'admin@legalapp.com',
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/rest/v1/users')) {
          return http.Response(
            jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'admin-uid',
                'uid': 'admin-uid',
                'auth_user_id': '00000000-0000-4000-8000-000000000001',
                'name': 'App Administrator',
                'email': 'admin@legalapp.com',
                'role': 'admin',
              },
            ]),
            200,
          );
        }
        return http.Response('{}', 404);
      });

      final api = FakeApiService();
      final authService = AuthService(
        api: api,
        supabaseHttpClient: client,
        supabaseUrl: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        supabaseAnonKey: 'public-anon-key',
      );

      final session = await authService.signIn('admin@legalapp.com', 'secret');
      expect(session.uid, 'admin-uid');
      expect(session.role, 'admin');
      expect(session.idToken, 'supa-admin-jwt');
      expect(await authService.freshToken(), 'supa-admin-jwt');
    });

    test('rejects a non-admin account in Supabase mode and clears the token', () async {
      final client = MockClient((request) async {
        if (request.url.path.endsWith('/auth/v1/token')) {
          return http.Response(
            jsonEncode(<String, dynamic>{
              'access_token': 'supa-client-jwt',
              'user': <String, dynamic>{
                'id': '00000000-0000-4000-8000-000000000002',
                'email': 'client@legalapp.com',
              },
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/rest/v1/users')) {
          return http.Response(
            jsonEncode(<Map<String, dynamic>>[
              <String, dynamic>{
                'id': 'client-001',
                'uid': 'client-001',
                'name': 'James Powell',
                'email': 'client@legalapp.com',
                'role': 'client',
              },
            ]),
            200,
          );
        }
        if (request.url.path.endsWith('/auth/v1/logout')) {
          return http.Response('', 204);
        }
        return http.Response('{}', 404);
      });

      final api = FakeApiService();
      final authService = AuthService(
        api: api,
        supabaseHttpClient: client,
        supabaseUrl: 'https://qqfzbecwhewswkyxgebu.supabase.co',
        supabaseAnonKey: 'public-anon-key',
      );

      await expectLater(
        authService.signIn('client@legalapp.com', 'secret'),
        throwsA(isA<NotAdminException>()),
      );
      expect(await authService.freshToken(), isNull);
    });
  });
}

/// An [AuthService] whose signIn() blocks on a completer, so the double-submit
/// guard can be exercised.
class _GatedSignInService implements AuthService {
  _GatedSignInService(this._gate);

  final Completer<AdminSession> _gate;

  /// Never supplied by a caller here; kept as a field because
  /// [currentUser] must return one. Defaults to `null`.
  AdminSession? session;

  @override
  final ApiService api = FakeApiService();

  int signInCalls = 0;

  @override
  Stream<User?> get authStateChanges => const Stream<User?>.empty();

  @override
  User? get currentFirebaseUser => null;

  @override
  Future<String?> freshToken() async => 't';

  @override
  Future<AdminSession> signIn(String email, String password) async {
    signInCalls++;
    return _gate.future;
  }

  @override
  Future<AdminSession?> currentUser() async => session;

  @override
  Future<void> signOut() async {}
}
