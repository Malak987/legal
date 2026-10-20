// Widget tests for the admin authentication flow.
//
// The app is mounted with an injected AuthProvider (see AdminApp.authProvider)
// backed by FakeAuthService / FakeApiService, so these tests need neither a
// live Firebase project nor network access.
//
// The regression test "tapping Sign In reads the provider without throwing"
// covers the reported crash:
//   "Tried to listen to a value exposed with provider, from outside of the
//    widget tree" — caused by AuthProvider.of() using context.watch().

import 'package:flutter_test/flutter_test.dart';
import 'package:legal_admin/main.dart';
import 'package:legal_admin/providers/auth_provider.dart';

import 'fakes.dart';

/// Mounts [AdminApp] with a pre-built provider and renders the first frames.
Future<void> pumpApp(WidgetTester tester, AuthProvider provider) async {
  await tester.pumpWidget(AdminApp(authProvider: provider));
  await tester.pump();
}

/// Canned `/api/dashboard/stats` payload (flat form is accepted by
/// DashboardScreen, which falls back to the root map when `data` is absent).
Map<String, dynamic> dashboardPayload() => <String, dynamic>{
      'users': 1,
      'lawyers': 2,
      'cases': 3,
      'bookings': 4,
      'reviews': 5,
      'plans': 3,
      'subscriptions': 0,
      'bookingsByStatus': <String, dynamic>{
        'active': 1,
        'completed': 2,
        'cancelled': 1,
      },
      'totalWalletBalance': 0,
    };

void main() {
  testWidgets('shows the loading gate while the auth status is unknown',
      (WidgetTester tester) async {
    final provider = AuthProvider(FakeAuthService(api: FakeApiService()));

    await pumpApp(tester, provider);

    expect(provider.status, AuthStatus.unknown);
    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('shows the login screen when there is no persisted session',
      (WidgetTester tester) async {
    final provider = AuthProvider(
      FakeAuthService(api: FakeApiService(), restoredSession: null),
    );

    await pumpApp(tester, provider);
    await provider.restore();
    await tester.pump();

    expect(provider.status, AuthStatus.unauthenticated);
    expect(find.text('Sign In'), findsOneWidget);
    expect(find.text('Admin Panel'), findsOneWidget);
  });

  testWidgets('shows the admin shell when an admin session is restored',
      (WidgetTester tester) async {
    final provider = AuthProvider(
      FakeAuthService(
        api: FakeApiService(result: dashboardPayload()),
        restoredSession: adminSession(),
      ),
    );

    await pumpApp(tester, provider);
    await provider.restore();
    await tester.pump();
    await tester.pump();

    expect(provider.status, AuthStatus.authenticated);
    expect(find.text('Dashboard'), findsWidgets);
    expect(find.text('Sign In'), findsNothing);
  });

  testWidgets('an unauthenticated user never sees the admin shell',
      (WidgetTester tester) async {
    final provider = AuthProvider(
      FakeAuthService(api: FakeApiService(), restoredSession: null),
    );

    await pumpApp(tester, provider);
    await provider.restore();
    await tester.pump();

    expect(provider.status, AuthStatus.unauthenticated);
    expect(find.text('Sign In'), findsOneWidget);
    // The shell must not be reachable without an authenticated admin session.
    expect(find.text('Dashboard'), findsNothing);
  });

  testWidgets('tapping Sign In reads the provider without throwing',
      (WidgetTester tester) async {
    // Regression test for the reported crash. AuthProvider.of() used
    // context.watch(), which throws when called from an onPressed handler.
    final service = FakeAuthService(
      api: FakeApiService(),
      signInError: Exception('[firebase_auth/invalid-credential] nope'),
    );
    final provider = AuthProvider(service);

    await pumpApp(tester, provider);
    await provider.restore();
    await tester.pump();

    expect(find.text('Sign In'), findsOneWidget);

    // If this throws, the test fails — that is the regression signal.
    await tester.tap(find.text('Sign In'));
    await tester.pump(); // isLoading -> spinner
    await tester.pump(); // signIn future completes
    await tester.pump(const Duration(milliseconds: 750)); // snackbar animates in

    expect(service.signInCalls, 1);
    expect(service.lastEmail, 'admin@legalapp.com');
    expect(provider.status, AuthStatus.unauthenticated);
    expect(provider.isLoading, isFalse,
        reason: 'must not remain in a loading state after a failed sign-in');
    expect(find.text('Incorrect email or password.'), findsOneWidget);
  });

  testWidgets('a successful admin sign-in opens the admin shell',
      (WidgetTester tester) async {
    final api = FakeApiService(result: dashboardPayload());
    final service = FakeAuthService(api: api, session: adminSession());
    final provider = AuthProvider(service);

    await pumpApp(tester, provider);
    await provider.restore();
    await tester.pump();

    expect(find.text('Sign In'), findsOneWidget);

    await tester.tap(find.text('Sign In'));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(service.signInCalls, 1);
    expect(provider.status, AuthStatus.authenticated);
    expect(provider.session?.role, 'admin');
    expect(find.text('Dashboard'), findsWidgets);
    expect(api.calls, contains('GET dashboard/stats'));
  });

  testWidgets('a non-admin account is rejected at the login screen',
      (WidgetTester tester) async {
    final service = FakeAuthService(
      api: FakeApiService(),
      signInError: Exception(
        'This account is not an administrator (role: client).',
      ),
    );
    final provider = AuthProvider(service);

    await pumpApp(tester, provider);
    await provider.restore();
    await tester.pump();

    await tester.tap(find.text('Sign In'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(provider.isAuthenticated, isFalse);
    expect(provider.session, isNull);
    expect(find.text('Dashboard'), findsNothing);
    expect(find.textContaining('not an administrator'), findsOneWidget);
  });
}
