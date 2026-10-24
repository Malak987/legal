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

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_admin/main.dart';
import 'package:legal_admin/providers/auth_provider.dart';

import 'fakes.dart';

/// Mounts [AdminApp] with a pre-built provider and renders the first frames.
Future<void> pumpApp(WidgetTester tester, AuthProvider provider) async {
  await tester.pumpWidget(AdminApp(authProvider: provider));
  await tester.pump();
}

/// Types a password so the login form validates.
///
/// `LoginScreen._submit()` returns early when `Form.validate()` fails, and the
/// password field is required. The email field is pre-filled with the default
/// admin address, so only the password is missing from a freshly mounted form.
Future<void> enterPassword(
  WidgetTester tester, [
  String password = 'secret-password',
]) async {
  final passwordField = find.byWidgetPredicate(
    (widget) => widget is TextField && widget.obscureText,
  );
  expect(passwordField, findsOneWidget);
  await tester.enterText(passwordField, password);
  await tester.pump();
}

/// Canned `/api/dashboard/stats` payload, in the backend's real envelope
/// `{ success, message, data }` (see `ok()` in backend/src/utils/response.js).
Map<String, dynamic> emptyPage() => <String, dynamic>{
      'success': true,
      'message': 'OK',
      'data': <String, dynamic>{
        'items': <Map<String, dynamic>>[],
        'total': 0,
        'page': 1,
        'limit': 100,
        'totalPages': 0,
      },
    };

Map<String, dynamic> dashboardPayload() => <String, dynamic>{
      'success': true,
      'message': 'OK',
      'data': <String, dynamic>{
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
      },
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
    expect(find.text('Admin & Lawyer Workspace'), findsOneWidget);
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

  testWidgets('lawyers get only the scoped read-only workspace',
      (WidgetTester tester) async {
    final api = FakeApiService(resultsByPath: <String, Object?>{
      'cases': emptyPage(),
      'bookings': emptyPage(),
      'availability/mine': emptyPage(),
    });
    final provider = AuthProvider(
      FakeAuthService(api: api, restoredSession: lawyerSession()),
    );

    await pumpApp(tester, provider);
    await provider.restore();
    await tester.pumpAndSettle();

    expect(provider.session?.role, 'lawyer');
    expect(find.text('Overview'), findsWidgets);
    expect(find.textContaining('does not provide client or case editing'), findsOneWidget);
    expect(api.calls, containsAll(<String>[
      'GET cases',
      'GET bookings',
      'GET availability/mine',
    ]));

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    expect(find.text('My Cases'), findsWidgets);
    expect(find.text('My Bookings'), findsWidgets);
    expect(find.text('My Availability'), findsOneWidget);
    expect(find.text('Users'), findsNothing);
    expect(find.text('Lawyers'), findsNothing);
    expect(find.text('Categories'), findsNothing);

    await tester.tap(find.descendant(
      of: find.byType(Drawer),
      matching: find.text('My Cases'),
    ).first);
    await tester.pumpAndSettle();
    final drawerContext = tester.element(find.byType(Drawer));
    Navigator.of(drawerContext).pop();
    await tester.pumpAndSettle();
    expect(find.text('No cases are assigned to your profile'), findsOneWidget);
    expect(find.text('Add Case'), findsNothing);
    expect(find.byIcon(Icons.edit), findsNothing);
    expect(find.byIcon(Icons.delete), findsNothing);

    await tester.tap(find.byTooltip('Open navigation menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(
      of: find.byType(Drawer),
      matching: find.text('My Bookings'),
    ).first);
    await tester.pumpAndSettle();
    Navigator.of(tester.element(find.byType(Drawer))).pop();
    await tester.pumpAndSettle();
    expect(find.text('No appointments are assigned to your profile'), findsOneWidget);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
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
    await enterPassword(tester);

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
    await enterPassword(tester);

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
        'This account is not authorized for the internal panel (role: client).',
      ),
    );
    final provider = AuthProvider(service);

    await pumpApp(tester, provider);
    await provider.restore();
    await tester.pump();

    await enterPassword(tester);
    await tester.tap(find.text('Sign In'));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 750));

    expect(provider.isAuthenticated, isFalse);
    expect(provider.session, isNull);
    expect(find.text('Dashboard'), findsNothing);
    expect(find.textContaining('not authorized for the internal panel'), findsOneWidget);
  });
}
