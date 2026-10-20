import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'api_service.dart';

/// Holds the signed-in administrator's session.
class AdminSession {
  final String uid;
  final String email;
  final String name;
  final String role;
  final String idToken;

  AdminSession({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    required this.idToken,
  });
}

/// Handles administrator authentication using Firebase Authentication and
/// verifies the user's role from the Firestore `users` collection.
class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? db, ApiService? api})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance,
        _api = api ?? ApiService();

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final ApiService _api;

  ApiService get api => _api;

  /// Signs in with email/password and ensures the account has the admin role.
  Future<AdminSession> signIn(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw Exception('Sign-in failed: no user returned.');
    }

    // Make sure the account is an administrator.
    final doc = await _db.collection('users').doc(firebaseUser.uid).get();
    final data = doc.data() ?? {};
    final role = (data['role'] ?? 'client').toString();

    if (role != 'admin') {
      await _auth.signOut();
      throw Exception(
        'This account is not an administrator (role: $role).',
      );
    }

    final idToken = await firebaseUser.getIdToken();

    // Share the token with the API client for subsequent requests.
    _api.token = idToken;

    return AdminSession(
      uid: firebaseUser.uid,
      email: firebaseUser.email ?? email,
      name: data['name']?.toString() ?? firebaseUser.displayName ?? 'Admin',
      role: role,
      idToken: idToken ?? '',
    );
  }

  /// Returns the current administrator (if any) by restoring the token.
  ///
  /// Mirrors the role enforcement in [signIn]: a signed-in Firebase account
  /// whose Firestore `role` is not `admin` must never be treated as an
  /// administrator, otherwise a restored `client`/`lawyer` session would be
  /// able to enter the admin dashboard.
  Future<AdminSession?> currentUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;

    final doc = await _db.collection('users').doc(firebaseUser.uid).get();
    final data = doc.data() ?? {};
    final role = (data['role'] ?? 'client').toString();

    if (role != 'admin') {
      // Consistent with signIn(): never leave a non-admin session active here.
      await _auth.signOut();
      _api.token = null;
      return null;
    }

    final idToken = await firebaseUser.getIdToken();
    _api.token = idToken;

    return AdminSession(
      uid: firebaseUser.uid,
      email: firebaseUser.email ?? '',
      name: data['name']?.toString() ?? firebaseUser.displayName ?? 'Admin',
      role: role,
      idToken: idToken ?? '',
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _api.token = null;
  }
}
