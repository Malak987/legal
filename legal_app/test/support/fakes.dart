import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:legalserviceapp/services/api_client.dart';
import 'package:legalserviceapp/services/auth_service.dart';

/// An [AuthGateway] with no Firebase behind it.
///
/// Tracks the calls that matter for the lifecycle rules — especially
/// `deleteCurrentAccount`, which must only ever remove an account created by
/// the current attempt.
class FakeAuthGateway implements AuthGateway {
  FakeAuthGateway({AuthUser? initialUser}) : _current = initialUser;

  final StreamController<AuthUser?> _changes =
      StreamController<AuthUser?>.broadcast();

  AuthUser? _current;

  /// Failures the next call should throw, or `null` for success.
  AuthException? createAccountError;
  AuthException? signInError;
  bool failDelete = false;

  /// When false, sign-in/sign-up update [currentUser] but do not push the
  /// change onto the stream — modelling a Firebase event that arrives later
  /// (or never). Sign-out always emits, as the real SDK does.
  bool emitAuthEvents = true;

  int createAccountCalls = 0;
  int signInCalls = 0;
  int deleteCalls = 0;
  int signOutCalls = 0;

  @override
  Stream<AuthUser?> get authStateChanges => _changes.stream;

  @override
  AuthUser? get currentUser => _current;

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    signInCalls++;
    final error = signInError;
    if (error != null) throw error;
    final user = AuthUser(uid: 'uid-${email.hashCode.abs()}', email: email);
    _set(user, emit: emitAuthEvents);
    return user;
  }

  @override
  Future<AuthUser> createAccount({
    required String email,
    required String password,
  }) async {
    createAccountCalls++;
    final error = createAccountError;
    if (error != null) throw error;
    final user = AuthUser(uid: 'uid-new', email: email);
    _set(user, emit: emitAuthEvents);
    return user;
  }

  @override
  Future<void> deleteCurrentAccount() async {
    deleteCalls++;
    if (failDelete) {
      throw const FirebaseAuthExceptionLike('requires-recent-login');
    }
    _set(null);
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    _set(null);
  }

  /// Emits an auth change, as the Firebase stream would.
  void emit(AuthUser? user) => _set(user);

  void _set(AuthUser? user, {bool emit = true}) {
    _current = user;
    if (emit && !_changes.isClosed) _changes.add(user);
  }

  Future<void> dispose() => _changes.close();
}

/// Stand-in for a rollback failure that the service should report rather than
/// swallow.
class FirebaseAuthExceptionLike implements Exception {
  const FirebaseAuthExceptionLike(this.code);
  final String code;
}

/// A 200 response carrying the backend's `{ success, data }` envelope.
http.Response jsonOk(Object? data, {int status = 200}) {
  return http.Response(
    jsonEncode({'success': true, 'data': data}),
    status,
    headers: {'content-type': 'application/json'},
  );
}

/// An error response in the same envelope, with a `message`.
http.Response jsonError(int status, String message) {
  return http.Response(
    jsonEncode({'success': false, 'message': message}),
    status,
    headers: {'content-type': 'application/json'},
  );
}

/// An [ApiClient] wired to a [MockClient], so no socket is ever opened.
///
/// [handler] receives the request and the number of times that exact
/// method+path pair has been seen, which is how retry behaviour is asserted.
ApiClient testApiClient({
  required Future<http.Response> Function(http.Request request, int attempt)
      handler,
  String uid = 'uid-1',
  String token = 'test-token',
  Duration requestTimeout = ApiClient.defaultRequestTimeout,
}) {
  final counts = <String, int>{};
  final client = MockClient((request) async {
    final key = '${request.method} ${request.url.path}';
    final attempt = (counts[key] ?? 0) + 1;
    counts[key] = attempt;
    return handler(request, attempt);
  });

  return ApiClient(
    baseUrl: 'http://test.local/api',
    client: client,
    idTokenProvider: () async => token,
    currentUidProvider: () => uid,
    requestTimeout: requestTimeout,
  );
}

/// Convenience: a profile document as `GET /api/users/:id` returns it.
Map<String, dynamic> profileJson({
  String id = 'uid-1',
  String name = 'Sara Ali',
  String email = 'sara@example.com',
  String role = 'client',
  String? phone,
  String? address,
}) {
  return {
    'id': id,
    'name': name,
    'email': email,
    'role': role,
    if (phone != null) 'phone': phone,
    if (address != null) 'address': address,
  };
}
