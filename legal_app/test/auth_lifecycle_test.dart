import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:legalserviceapp/services/api_client.dart';
import 'package:legalserviceapp/services/auth_service.dart';
import 'package:legalserviceapp/state/session_controller.dart';
import 'package:legalserviceapp/state/start_route.dart';

import 'support/fakes.dart';

/// Lets queued microtasks (and the stream listeners) run.
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('AuthService.register', () {
    test('creates the account, then provisions the profile', () async {
      final gateway = FakeAuthGateway();
      final calls = <String>[];
      final api = testApiClient(handler: (request, _) async {
        calls.add('${request.method} ${request.url.path}');
        if (request.method == 'POST') {
          return jsonOk(profileJson(name: 'Sara'), status: 201);
        }
        return jsonOk(profileJson(name: 'Sara'));
      });
      final auth = AuthService(gateway: gateway, api: api);

      final profile = await auth.register(
        name: 'Sara',
        email: 'sara@example.com',
        password: 'secret123',
      );

      expect(profile.name, 'Sara');
      expect(calls, ['POST /api/users/me', 'GET /api/users/uid-1']);
      expect(gateway.deleteCalls, 0);
    });

    test('a rejected credential never touches a rolled-back account', () async {
      final gateway = FakeAuthGateway()
        ..createAccountError =
            AuthException('An account with this email already exists.');
      final api = testApiClient(handler: (_, __) async => jsonOk(profileJson()));
      final auth = AuthService(gateway: gateway, api: api);

      await expectLater(
        auth.register(name: 'Sara', email: 'sara@example.com', password: 'x'),
        throwsA(isA<AuthException>()),
      );

      // The account was never created by this attempt, so it must not be
      // deleted — it may belong to somebody else.
      expect(gateway.createAccountCalls, 1);
      expect(gateway.deleteCalls, 0);
    });

    test('provisioning failure rolls back the account just created', () async {
      final gateway = FakeAuthGateway();
      final api = testApiClient(
        handler: (_, __) async => jsonError(500, 'Server exploded'),
      );
      final auth = AuthService(gateway: gateway, api: api);

      await expectLater(
        auth.register(name: 'Sara', email: 'sara@example.com', password: 'x'),
        throwsA(isA<AuthException>()
            .having((e) => e.accountCreated, 'accountCreated', isFalse)),
      );

      expect(gateway.deleteCalls, 1);
      expect(gateway.currentUser, isNull);
    });

    test('a failed rollback is reported instead of hidden', () async {
      final gateway = FakeAuthGateway()..failDelete = true;
      final api = testApiClient(
        handler: (_, __) async => jsonError(500, 'Server exploded'),
      );
      final auth = AuthService(gateway: gateway, api: api);

      await expectLater(
        auth.register(name: 'Sara', email: 'sara@example.com', password: 'x'),
        throwsA(isA<AuthException>()
            .having((e) => e.accountCreated, 'accountCreated', isTrue)),
      );

      expect(gateway.deleteCalls, 1);
      // The account still exists; the message must say so.
      expect(gateway.currentUser, isNotNull);
    });

    test('a retry when the profile exists keeps the stored data', () async {
      final gateway = FakeAuthGateway();
      final api = testApiClient(handler: (request, _) async {
        if (request.method == 'POST') {
          return jsonError(409, 'A profile already exists for this account.');
        }
        // A profile created by an earlier attempt — trusted data wins.
        return jsonOk(profileJson(name: 'Original Name', role: 'lawyer'));
      });
      final auth = AuthService(gateway: gateway, api: api);

      final profile = await auth.register(
        name: 'Different Name',
        email: 'sara@example.com',
        password: 'x',
      );

      expect(profile.name, 'Original Name');
      expect(profile.role, 'lawyer');
      expect(gateway.deleteCalls, 0, reason: 'the account was not rolled back');
    });
  });

  group('AuthService.loadOrProvisionProfile', () {
    test('returns an existing profile without provisioning', () async {
      final gateway = FakeAuthGateway(
        initialUser: const AuthUser(uid: 'uid-1', email: 'sara@example.com'),
      );
      var posts = 0;
      final api = testApiClient(handler: (request, _) async {
        if (request.method == 'POST') posts++;
        return jsonOk(profileJson());
      });

      final profile =
          await AuthService(gateway: gateway, api: api).loadOrProvisionProfile();

      expect(profile.uid, 'uid-1');
      expect(posts, 0);
    });

    test('provisions a legacy account with a default client name', () async {
      final gateway = FakeAuthGateway(
        initialUser: const AuthUser(uid: 'uid-1', email: 'sara.ali@example.com'),
      );
      final bodies = <String>[];
      var gets = 0;
      final api = testApiClient(handler: (request, _) async {
        if (request.method == 'POST') {
          bodies.add(request.body);
          return jsonOk(profileJson(name: 'sara.ali'), status: 201);
        }
        // Missing before provisioning, present afterwards.
        gets++;
        return gets == 1
            ? jsonError(404, 'User not found')
            : jsonOk(profileJson(name: 'sara.ali'));
      });

      final profile = await AuthService(gateway: gateway, api: api)
          .loadOrProvisionProfile();

      expect(profile.name, 'sara.ali');
      expect(bodies.single, contains('sara.ali'));
      expect(bodies.single, isNot(contains('role')));
    });

    test('never provisions when the failure is not a 404', () async {
      final gateway = FakeAuthGateway(
        initialUser: const AuthUser(uid: 'uid-1', email: 'sara@example.com'),
      );
      var posts = 0;
      final api = testApiClient(handler: (request, _) async {
        if (request.method == 'POST') posts++;
        return jsonError(500, 'Server exploded');
      });

      await expectLater(
        AuthService(gateway: gateway, api: api).loadOrProvisionProfile(),
        throwsA(isA<ApiException>()),
      );
      expect(posts, 0);
    });

    test('refuses to run without a session', () async {
      final api = testApiClient(handler: (_, __) async => jsonOk(profileJson()));
      await expectLater(
        AuthService(gateway: FakeAuthGateway(), api: api)
            .loadOrProvisionProfile(),
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
      expect(session.status, SessionStatus.signedOut);
      expect(gateway.deleteCalls, 1);
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

    test('a profile update adopts the role the server returns', () async {
      // Signed in as a lawyer, then demoted by an administrator: the next
      // response must lower the cached role rather than keep a stale one.
      final session = build(
        responder: (method) => method == 'PUT'
            ? jsonOk(profileJson(role: 'client', name: 'Sara'))
            : jsonOk(profileJson(role: 'lawyer')),
      );
      await session.signIn(email: 'sara@example.com', password: 'secret123');
      await settle();
      expect(session.profile?.role, 'lawyer');

      await session.updateProfile(
        name: 'Sara',
        email: 'sara@example.com',
      );

      expect(session.profile?.role, 'client');
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

    test('a restored Firebase session loads the profile exactly once',
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
}
