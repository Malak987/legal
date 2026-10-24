// Test doubles for the admin panel.
//
// These let the auth flow be exercised without a live Supabase project and
// without any network access. They implement the real service classes (using
// Dart's implicit interfaces) so no production code needs to change shape and
// no additional test packages are required.

import 'dart:async';

import 'package:legal_admin/services/api_service.dart';
import 'package:legal_admin/services/auth_service.dart';

class MemoryAdminSessionStore implements AdminSessionStore {
  String? refreshToken;

  @override
  Future<String?> readRefreshToken() async => refreshToken;

  @override
  Future<void> writeRefreshToken(String token) async {
    refreshToken = token;
  }

  @override
  Future<void> clear() async {
    refreshToken = null;
  }
}

/// One recorded request, with everything a test may need to assert on.
class FakeRequest {
  FakeRequest({
    required this.method,
    required this.path,
    this.query = const <String, String>{},
    this.body,
  });

  final String method;
  final String path;
  final Map<String, String> query;
  final Object? body;

  /// `GET users` style label, matching the historical `calls` entries.
  String get label => '$method $path';

  @override
  String toString() => '$label query=$query body=$body';
}

/// In-memory [ApiService]: records calls and returns canned payloads.
///
/// Backwards compatible with the original single-`result` fake: with no
/// [resultsByPath], every verb still returns [result]. The additions are
/// per-path payloads, captured query strings and bodies, and injectable
/// failures — all needed to test a screen that loads one path and saves
/// another.
class FakeApiService implements ApiService {
  FakeApiService({this.result, Map<String, Object?>? resultsByPath})
      : _resultsByPath = resultsByPath ?? const <String, Object?>{};

  /// The value returned by every verb that has no entry in [resultsByPath].
  final Object? result;

  /// When set, every request waits for this before resolving.
  ///
  /// Lets a test hold a response open and assert on a loading state without
  /// racing the frame in which the widget is first built.
  Completer<void>? gate;

  /// Payload (or [ApiException]/[Error] to throw) per path, e.g. `'users'`.
  final Map<String, Object?> _resultsByPath;

  /// Every recorded request, with query parameters and body.
  final List<FakeRequest> requests = <FakeRequest>[];

  /// Every request made, e.g. `GET dashboard/stats`.
  ///
  /// Kept for the existing tests, which assert on this shape.
  final List<String> calls = <String>[];

  /// Requests matching [method] and [path], newest last.
  List<FakeRequest> requestsFor(String method, String path) => requests
      .where((r) => r.method == method && r.path == path)
      .toList();

  /// The body of the most recent [method] [path] request, if any.
  Object? lastBodyFor(String method, String path) {
    final matches = requestsFor(method, path);
    return matches.isEmpty ? null : matches.last.body;
  }

  Future<void> _awaitGate() async {
    final pending = gate;
    if (pending != null) await pending.future;
  }

  /// Adds a canned response only when a test has not configured that path.
  void setDefaultResult(String path, Object? value) {
    _resultsByPath.putIfAbsent(path, () => value);
  }

  Object? _resolve(String path) {
    final entry = _resultsByPath[path];
    if (entry is Error) throw entry;
    if (entry is Exception) throw entry;
    if (_resultsByPath.containsKey(path)) return entry;
    return result;
  }

  void _record(String method, String path, Map<String, String> query, Object? body) {
    calls.add('$method $path');
    requests.add(
      FakeRequest(
        method: method,
        path: path,
        query: Map<String, String>.from(query),
        body: body,
      ),
    );
  }

  @override
  String? token;

  @override
  Future<String?> Function()? tokenProvider;

  /// The `Authorization` header attached to the most recent request.
  String? lastAuthHeader;

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    _record('GET', path, query ?? const <String, String>{}, null);
    await _captureToken();
    await _awaitGate();
    return _resolve(path);
  }

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    _record('POST', path, const <String, String>{}, body);
    await _captureToken();
    await _awaitGate();
    return _resolve(path);
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    _record('PUT', path, const <String, String>{}, body);
    await _captureToken();
    await _awaitGate();
    return _resolve(path);
  }

  @override
  Future<dynamic> delete(String path) async {
    _record('DELETE', path, const <String, String>{}, null);
    await _captureToken();
    await _awaitGate();
    return _resolve(path);
  }

  Future<void> _captureToken() async {
    final provider = tokenProvider;
    String? effective = token;
    if (provider != null) {
      final fresh = await provider();
      if (fresh != null && fresh.isNotEmpty) effective = fresh;
    }
    lastAuthHeader =
        effective == null || effective.isEmpty ? null : 'Bearer $effective';
  }

  @override
  void dispose() {}
}

/// In-memory [AuthService]: drives [AuthProvider] without Supabase.
class FakeAuthService implements AuthService {
  FakeAuthService({
    required this.api,
    this.session,
    this.restoredSession,
    this.signInError,
    this.currentUserError,
    this.currentUserGate,
    this.token = 'fake-id-token',
  });

  @override
  final ApiService api;

  /// Returned by a successful [signIn].
  final AdminSession? session;

  /// Returned by [currentUser]. `null` means "no persisted session".
  AdminSession? restoredSession;

  /// When set, [signIn] throws this instead of returning a session.
  Object? signInError;

  /// When set, [currentUser] throws this instead of returning a session.
  Object? currentUserError;

  /// When set, [currentUser] blocks until this completer completes. Used to
  /// simulate a slow profile read that finishes *after* a sign-in.
  Completer<AdminSession?>? currentUserGate;

  /// Value returned by [freshToken].
  final String? token;

  int signInCalls = 0;
  int currentUserCalls = 0;
  int signOutCalls = 0;
  int freshTokenCalls = 0;
  int resetPasswordCalls = 0;
  String? lastResetEmail;
  String? lastEmail;
  String? lastPassword;

  final StreamController<AdminAuthUser?> _authController =
      StreamController<AdminAuthUser?>.broadcast();

  @override
  Stream<AdminAuthUser?> get authStateChanges => _authController.stream;

  @override
  bool get isConfigured => true;

  /// Emits an explicit Supabase auth-state change.
  void emitAuthState(AdminAuthUser? user) => _authController.add(user);

  @override
  Future<AdminSession> signIn(String email, String password) async {
    signInCalls++;
    lastEmail = email;
    lastPassword = password;
    final error = signInError;
    if (error != null) throw error;
    return session!;
  }

  @override
  Future<AdminSession?> currentUser() async {
    currentUserCalls++;
    final gate = currentUserGate;
    if (gate != null) await gate.future;
    final error = currentUserError;
    if (error != null) throw error;
    return restoredSession;
  }

  @override
  Future<String?> freshToken({bool forceRefresh = false}) async {
    freshTokenCalls++;
    return token;
  }

  @override
  Future<void> requestPasswordReset(String email) async {
    resetPasswordCalls++;
    lastResetEmail = email;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    api.token = null;
  }

  @override
  void dispose() {
    if (!_authController.isClosed) _authController.close();
  }
}

/// A canonical administrator session used across the tests.
AdminSession adminSession() => AdminSession(
      uid: 'admin-uid',
      email: 'admin@legalapp.com',
      name: 'App Administrator',
      role: 'admin',
      idToken: 'fake-id-token',
    );

/// A server-verified lawyer session for read-only workspace tests.
AdminSession lawyerSession() => AdminSession(
      uid: 'lawyer-001',
      email: 'lawyer@legalapp.com',
      name: 'Test Lawyer',
      role: 'lawyer',
      idToken: 'fake-lawyer-id-token',
    );

/// A separately provisioned owner session for admin-shell tests.
AdminSession ownerSession() => AdminSession(
      uid: 'owner-001',
      email: 'owner@legalapp.com',
      name: 'Test Owner',
      role: 'owner',
      idToken: 'fake-owner-id-token',
    );

/// A session for an account that must never reach the internal panel.
AdminSession clientSession() => AdminSession(
      uid: 'client-001',
      email: 'client@example.com',
      name: 'James Powell',
      role: 'client',
      idToken: 'fake-id-token',
    );
