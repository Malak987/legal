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

/// The Firestore profile could not be read because of a **transient** problem
/// (network down, offline, permission error, cold cache, ...).
///
/// The session may still be perfectly valid — callers MUST NOT sign the user
/// out when this is thrown. They should surface the message and offer a retry.
class ProfileReadException implements Exception {
  ProfileReadException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// There is definitively **no** `users/{uid}` document for this account.
///
/// This is a confirmed fact read from the server, so ending the session is
/// safe and correct.
class AdminProfileMissingException implements Exception {
  AdminProfileMissingException(this.uid);

  final String uid;

  @override
  String toString() =>
      'No user profile found for this account (users/$uid). '
      'Ask an administrator to create it, or seed the database.';
}

/// The profile exists but its role is not `admin`.
class NotAdminException implements Exception {
  NotAdminException(this.role);

  final String role;

  @override
  String toString() => 'This account is not an administrator (role: $role).';
}

/// Handles administrator authentication using Firebase Authentication and
/// verifies the user's role from the Firestore `users` collection.
class AuthService {
  AuthService({FirebaseAuth? auth, FirebaseFirestore? db, ApiService? api})
      : _auth = auth ?? FirebaseAuth.instance,
        _db = db ?? FirebaseFirestore.instance,
        _api = api ?? ApiService() {
    // Firebase ID tokens expire after one hour. Give the HTTP client a way to
    // obtain a fresh one for every protected request.
    _api.tokenProvider = freshToken;
  }

  final FirebaseAuth _auth;
  final FirebaseFirestore _db;
  final ApiService _api;

  ApiService get api => _api;

  /// Firebase auth-state stream. [AuthProvider] subscribes exactly once.
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  /// The currently signed-in Firebase user, if any (may be null while the SDK
  /// is still restoring the persisted session on web).
  User? get currentFirebaseUser => _auth.currentUser;

  /// Returns a valid Firebase ID token, refreshing it when it has expired.
  ///
  /// Falls back to the last known token if a refresh is not possible, so a
  /// transient failure never blanks the Authorization header mid-session.
  Future<String?> freshToken() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    try {
      final String? token = await user.getIdToken();
      _api.token = token;
      return token;
    } catch (_) {
      return _api.token;
    }
  }

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

    final data = await _loadProfileOrEndSession(firebaseUser.uid);
    final role = _roleOf(data);

    if (role != 'admin') {
      await _endSession();
      throw NotAdminException(role);
    }

    final idToken = await firebaseUser.getIdToken();
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
  /// Enforces exactly the same `role == 'admin'` rule as [signIn].
  /// A transient read failure is surfaced as [ProfileReadException] and never
  /// destroys the underlying Firebase session.
  Future<AdminSession?> currentUser() async {
    final firebaseUser = _auth.currentUser;
    if (firebaseUser == null) return null;

    final data = await _loadProfileOrEndSession(firebaseUser.uid);
    final role = _roleOf(data);

    if (role != 'admin') {
      await _endSession();
      throw NotAdminException(role);
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
    await _endSession();
  }

  // ------------------------------------------------------------------
  //  Internals
  // ------------------------------------------------------------------

  /// Reads `users/{uid}` **from the server** and ends the session only for
  /// definitive outcomes (profile missing). Transient failures are rethrown as
  /// [ProfileReadException] and leave the Firebase session untouched.
  Future<Map<String, dynamic>> _loadProfileOrEndSession(String uid) async {
    Map<String, dynamic> data;
    try {
      data = await _readProfileFromServer(uid);
    } on ProfileReadException {
      rethrow; // transient — keep the session, let the UI retry
    } catch (_) {
      await _endSession(); // definitive — no profile means no admin access
      rethrow;
    }
    return data;
  }

  /// Reads the profile document straight from the server.
  ///
  /// An empty or cold local cache must never be treated as proof that the
  /// profile is missing: on Flutter Web the first read can be served from an
  /// empty cache, which previously caused valid admins to be signed out in a
  /// loop. Requiring `Source.server` makes "missing" a verified fact.
  Future<Map<String, dynamic>> _readProfileFromServer(String uid) async {
    DocumentSnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _db
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      throw ProfileReadException(
        'Could not read your admin profile from the server (${e.code}). '
        'Check your connection and your Firestore security rules, then retry.',
        cause: e,
      );
    } catch (e) {
      throw ProfileReadException(
        'Could not read your admin profile from the server ($e). '
        'Check your connection, then retry.',
        cause: e,
      );
    }

    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw AdminProfileMissingException(uid);
    }
    return data;
  }

  static String _roleOf(Map<String, dynamic> data) =>
      (data['role'] ?? 'client').toString();

  /// Ends the Firebase session and clears the API token. Best effort: it must
  /// never prevent the caller from reporting what went wrong.
  Future<void> _endSession() async {
    try {
      await _auth.signOut();
    } catch (_) {
      // Ignored on purpose — the caller still reports the real reason.
    }
    _api.token = null;
  }
}
