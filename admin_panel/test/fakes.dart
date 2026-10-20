// Test doubles for the admin panel.
//
// These let the auth flow be exercised without a live Firebase project and
// without any network access. They implement the real service classes (using
// Dart's implicit interfaces) so no production code needs to change shape and
// no extra packages (mockito, fake_cloud_firestore, ...) are required.

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:legal_admin/services/api_service.dart';
import 'package:legal_admin/services/auth_service.dart';

/// In-memory [ApiService]: records calls and returns a canned payload.
class FakeApiService implements ApiService {
  FakeApiService({this.result});

  /// The value returned by every verb. Defaults to an empty list payload.
  final Object? result;

  /// Every request made, e.g. `GET dashboard/stats`.
  final List<String> calls = <String>[];

  @override
  String? token;

  @override
  Future<String?> Function()? tokenProvider;

  /// The `Authorization` header attached to the most recent request.
  String? lastAuthHeader;

  @override
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    calls.add('GET $path');
    await _captureToken();
    return result;
  }

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    calls.add('POST $path');
    await _captureToken();
    return result;
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    calls.add('PUT $path');
    await _captureToken();
    return result;
  }

  @override
  Future<dynamic> delete(String path) async {
    calls.add('DELETE $path');
    await _captureToken();
    return result;
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

/// In-memory [AuthService]: drives [AuthProvider] without Firebase.
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
  /// simulate a slow Firestore read that finishes *after* a sign-in.
  Completer<AdminSession?>? currentUserGate;

  /// Value returned by [freshToken].
  final String? token;

  int signInCalls = 0;
  int currentUserCalls = 0;
  int signOutCalls = 0;
  int freshTokenCalls = 0;
  String? lastEmail;
  String? lastPassword;

  final StreamController<User?> _authController =
      StreamController<User?>.broadcast();

  @override
  Stream<User?> get authStateChanges => _authController.stream;

  @override
  User? get currentFirebaseUser => null;

  /// Emits a Firebase auth-state change (e.g. a server-side sign-out).
  void emitAuthState(User? user) => _authController.add(user);

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
  Future<String?> freshToken() async {
    freshTokenCalls++;
    return token;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    api.token = null;
  }

  void dispose() => _authController.close();
}

/// A canonical administrator session used across the tests.
AdminSession adminSession() => AdminSession(
      uid: 'admin-uid',
      email: 'admin@legalapp.com',
      name: 'App Administrator',
      role: 'admin',
      idToken: 'fake-id-token',
    );

/// A session for an account that must never reach the admin dashboard.
AdminSession clientSession() => AdminSession(
      uid: 'client-001',
      email: 'client@example.com',
      name: 'James Powell',
      role: 'client',
      idToken: 'fake-id-token',
    );
