// The old counter template test was removed: it asserted on a demo widget that
// no longer exists, so it could never pass against this app. These tests
// exercise the authentication boundary that now decides what the user sees.
//
// They run under `testWidgets`, which uses a fake clock. The session's profile
// load awaits real futures (MockClient), so each state change is driven inside
// `tester.runAsync` and awaited through the controller itself rather than by
// guessing how many microtask turns a `pump()` flushes. That keeps the tests
// deterministic instead of timing-dependent.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legalserviceapp/services/auth_service.dart';
import 'package:legalserviceapp/state/session_controller.dart';
import 'package:legalserviceapp/state/session_scope.dart';

import 'support/fakes.dart';

/// A stand-in for the app shell: what it shows depends entirely on the session.
class _Probe extends StatelessWidget {
  const _Probe();

  @override
  Widget build(BuildContext context) {
    final session = SessionScope.of(context);
    if (session.isResolving) {
      return const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('resolving'),
      );
    }
    if (session.isSignedIn) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Text('home:${session.profile?.displayName}'),
      );
    }
    return const Directionality(
      textDirection: TextDirection.ltr,
      child: Text('auth'),
    );
  }
}

void main() {
  late FakeAuthGateway gateway;
  late SessionController session;

  setUp(() {
    gateway = FakeAuthGateway();
    session = SessionController(
      auth: AuthService(
        gateway: gateway,
        api: testApiClient(handler: (_, __) async => jsonOk(profileJson())),
      ),
    );
  });

  tearDown(() => session.dispose());

  /// Runs real async until [done] is true, then renders one frame.
  ///
  /// Bounded, so a broken session fails the assertion below instead of hanging.
  Future<void> settle(
    WidgetTester tester,
    bool Function() done, {
    String reason = 'session never settled',
  }) async {
    await tester.runAsync(() async {
      for (var i = 0; i < 200 && !done(); i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    expect(done(), isTrue, reason: reason);
    await tester.pump();
  }

  testWidgets('protected UI is not shown while auth is still resolving',
      (tester) async {
    await tester.pumpWidget(
      SessionScope(controller: session, child: const _Probe()),
    );

    expect(find.text('resolving'), findsOneWidget);
    expect(find.text('auth'), findsNothing);
    expect(find.textContaining('home:'), findsNothing);
  });

  testWidgets('the signed-out state renders the auth flow', (tester) async {
    await tester.pumpWidget(
      SessionScope(controller: session, child: const _Probe()),
    );
    session.start();

    gateway.emit(null);
    await settle(tester, () => session.status == SessionStatus.signedOut);

    expect(find.text('auth'), findsOneWidget);
  });

  testWidgets('a loaded profile switches the shell to the signed-in UI',
      (tester) async {
    await tester.pumpWidget(
      SessionScope(controller: session, child: const _Probe()),
    );
    session.start();

    gateway.emit(const AuthUser(uid: 'uid-1', email: 'sara@example.com'));
    await settle(tester, () => session.isSignedIn);

    expect(find.text('home:Sara Ali'), findsOneWidget);
  });

  testWidgets('signing out returns to the auth flow', (tester) async {
    await tester.pumpWidget(
      SessionScope(controller: session, child: const _Probe()),
    );
    session.start();

    gateway.emit(const AuthUser(uid: 'uid-1', email: 'sara@example.com'));
    await settle(tester, () => session.isSignedIn);
    expect(find.text('home:Sara Ali'), findsOneWidget);

    await tester.runAsync(() => session.signOut());
    await settle(tester, () => session.status == SessionStatus.signedOut);

    expect(find.text('auth'), findsOneWidget);
    expect(find.text('home:Sara Ali'), findsNothing);
  });
}
