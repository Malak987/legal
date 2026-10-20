// Test doubles for the admin panel.
//
// These let the auth flow be exercised without a live Firebase project and
// without any network access. They implement the real service classes (using
// Dart's implicit interfaces) so no production code needs to change shape and
// no extra packages (mockito, fake_cloud_firestore, ...) are required.

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
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    calls.add('GET $path');
    return result;
  }

  @override
  Future<dynamic> post(String path, {Object? body}) async {
    calls.add('POST $path');
    return result;
  }

  @override
  Future<dynamic> put(String path, {Object? body}) async {
    calls.add('PUT $path');
    return result;
  }

  @override
  Future<dynamic> delete(String path) async {
    calls.add('DELETE $path');
    return result;
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
  });

  @override
  final ApiService api;

  /// Returned by a successful [signIn].
  final AdminSession? session;

  /// Returned by [currentUser]. `null` means "no persisted session".
  final AdminSession? restoredSession;

  /// When set, [signIn] throws this instead of returning a session.
  final Object? signInError;

  /// When set, [currentUser] throws this instead of returning a session.
  final Object? currentUserError;

  int signInCalls = 0;
  int currentUserCalls = 0;
  int signOutCalls = 0;
  String? lastEmail;
  String? lastPassword;

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
    final error = currentUserError;
    if (error != null) throw error;
    return restoredSession;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
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

/// A session for an account that must never reach the admin dashboard.
AdminSession clientSession() => AdminSession(
      uid: 'client-001',
      email: 'client@example.com',
      name: 'James Powell',
      role: 'client',
      idToken: 'fake-id-token',
    );
