// Unit tests for AuthProvider: sign-in outcomes and session restoration.
//
// These are pure Dart — no widgets — and use FakeAuthService / FakeApiService
// from test/fakes.dart, so they need no Firebase project and no network.

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_admin/providers/auth_provider.dart';

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

    test('invalid credentials surface a readable error and leave loading', () async {
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
        signInError: Exception(
          'This account is not an administrator (role: client).',
        ),
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

    test('a restored non-admin session is not treated as an admin', () async {
      // Regression guard: AuthService.currentUser() must apply the same
      // `role == 'admin'` check as signIn(). AuthProvider itself only reports
      // what the service returns, so this asserts the provider stays
      // unauthenticated whenever the service declines to return a session.
      final provider = AuthProvider(
        FakeAuthService(api: FakeApiService(), restoredSession: null),
      );

      await provider.restore();

      expect(provider.status, AuthStatus.unauthenticated);
      expect(provider.isAuthenticated, isFalse);
      expect(provider.session, isNull);
    });

    test('errors while restoring fall back to unauthenticated', () async {
      final provider = AuthProvider(
        FakeAuthService(
          api: FakeApiService(),
          currentUserError: Exception('network unavailable'),
        ),
      );

      await provider.restore();

      expect(provider.status, AuthStatus.unauthenticated);
      expect(provider.session, isNull);
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
      expect(service.signOutCalls, 1);
    });
  });
}
