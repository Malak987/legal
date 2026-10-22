import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_profile.dart';
import 'api_client.dart';

/// The signed-in Firebase account, reduced to what this app needs.
///
/// A plain value object rather than the plugin's `User`, so the session logic
/// can be exercised in tests without a live Firebase project.
class AuthUser {
  const AuthUser({required this.uid, this.email});

  final String uid;
  final String? email;

  String get emailOrEmpty => email ?? '';
}

/// A sign-in/registration failure with a message that can be shown as-is.
class AuthException implements Exception {
  AuthException(this.message, {this.code, this.accountCreated = false});

  final String message;

  /// Firebase's error code, when the failure came from Authentication.
  final String? code;

  /// True when registration left an Authentication account behind because the
  /// rollback itself failed. The UI says so instead of pretending nothing was
  /// created.
  final bool accountCreated;

  @override
  String toString() => message;
}

/// The Firebase Authentication operations the app performs.
///
/// Abstract so `SessionController` can be tested with a fake; the production
/// implementation is [FirebaseAuthGateway].
abstract class AuthGateway {
  /// Emits on sign-in, sign-out and token invalidation.
  Stream<AuthUser?> get authStateChanges;

  /// The currently signed-in account, or `null`.
  AuthUser? get currentUser;

  Future<AuthUser> signIn({required String email, required String password});

  Future<AuthUser> createAccount({
    required String email,
    required String password,
  });

  /// Deletes the account that is signed in **right now**.
  ///
  /// Used only to roll back an account created by the sign-up attempt that is
  /// still on the stack — never to "clean up" a pre-existing account.
  Future<void> deleteCurrentAccount();

  Future<void> signOut();

  /// Changes the signed-in account's password.
  ///
  /// Firebase requires a *recent* sign-in for this, so the current password is
  /// re-verified first: without that the call fails with `requires-recent-login`
  /// instead of succeeding, and the user gets no explanation.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
}

/// [AuthGateway] backed by the Firebase Authentication client SDK.
class FirebaseAuthGateway implements AuthGateway {
  /// Resolved per use, not in a field initialiser: `FirebaseAuth.instance`
  /// throws `[core/no-app]` when `Firebase.initializeApp` failed, which is the
  /// case on platforms whose options are still placeholders. `main()` catches
  /// that so the UI can load; the failure must surface here as a message, not
  /// as a crash while a screen is building.
  FirebaseAuth get _auth => FirebaseAuth.instance;

  AuthUser _map(User user) => AuthUser(uid: user.uid, email: user.email);

  @override
  Stream<AuthUser?> get authStateChanges =>
      _auth.authStateChanges().map((user) => user == null ? null : _map(user));

  @override
  AuthUser? get currentUser {
    try {
      final user = _auth.currentUser;
      return user == null ? null : _map(user);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw AuthException('Sign-in failed. Please try again.');
      }
      return _map(user);
    } on FirebaseAuthException catch (e) {
      throw AuthException(messageForAuthError(e), code: e.code);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(messageForSetupError(e));
    }
  }

  @override
  Future<AuthUser> createAccount({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        throw AuthException('Sign-up failed: no account was created.');
      }
      return _map(user);
    } on FirebaseAuthException catch (e) {
      throw AuthException(messageForAuthError(e), code: e.code);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(messageForSetupError(e));
    }
  }

  @override
  Future<void> deleteCurrentAccount() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await user.delete();
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw AuthException('You are not signed in.');
    }

    final email = user.email;
    if (email == null || email.isEmpty) {
      throw AuthException(
        'This account has no email address, so its password cannot be changed here.',
      );
    }

    try {
      // Re-authenticate first: `updatePassword` on a session older than a few
      // minutes is rejected with `requires-recent-login`, and a successful
      // re-auth is also what proves the person at the keyboard knows the
      // current password.
      final credential = EmailAuthProvider.credential(
        email: email,
        password: currentPassword,
      );
      await user.reauthenticateWithCredential(credential);
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (e) {
      throw AuthException(messageForAuthError(e), code: e.code);
    } on AuthException {
      rethrow;
    } catch (e) {
      throw AuthException(messageForSetupError(e));
    }
  }

  /// Maps Firebase error codes onto user-facing text.
  static String messageForAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return 'An account with this email already exists. Try signing in.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Choose a stronger password (at least 6 characters).';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'user-disabled':
        return 'This account has been disabled. Contact support.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      case 'network-request-failed':
        return 'Network error. Check your connection and try again.';
      case 'operation-not-allowed':
        return 'Email/password sign-in is not enabled for this project.';
      case 'requires-recent-login':
        return 'Please sign in again to finish this action.';
      default:
        return e.message ?? 'Authentication failed. Please try again.';
    }
  }

  /// Failures that are not `FirebaseAuthException`: most often a build whose
  /// Firebase options are still placeholders.
  static String messageForSetupError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('no-app') || text.contains('no firebase app')) {
      return 'Authentication is not configured for this build.';
    }
    return 'Could not reach authentication. Check your connection and retry.';
  }
}

/// Sign-in, registration and profile loading — the rules, not the transport.
///
/// Registration is split so the password never reaches this backend:
///
///  1. the Firebase client SDK creates the Authentication account;
///  2. `POST /api/users/me` creates `users/{uid}` with the server-assigned
///     `client` role (uid and email come from the verified token).
///
/// Step 2 failing rolls step 1 back, so a failed sign-up cannot leave an
/// account that authenticates but has no profile — invisible to the admin
/// panel, which lists Firestore rather than Authentication.
class AuthService {
  AuthService({required this.gateway, required this.api});

  final AuthGateway gateway;
  final ApiClient api;

  Stream<AuthUser?> get authStateChanges => gateway.authStateChanges;

  AuthUser? get currentUser => gateway.currentUser;

  /// Signs in and returns the account's profile, provisioning it when missing.
  ///
  /// A pre-existing profile is never overwritten: provisioning answers 409 and
  /// the stored document (including a `lawyer`/`admin` role) is left as it is.
  Future<AppProfile> signIn({
    required String email,
    required String password,
  }) async {
    await gateway.signIn(email: email, password: password);
    return loadOrProvisionProfile();
  }

  /// Creates the Authentication account and its Firestore profile.
  ///
  /// Throws [AuthException] on any failure. When the profile cannot be created
  /// the account created by *this call* is deleted again; if that rollback
  /// fails too, the exception reports `accountCreated: true`.
  Future<AppProfile> register({
    required String name,
    required String email,
    required String password,
  }) async {
    await gateway.createAccount(email: email, password: password);

    try {
      await api.provisionProfile(name: name);
    } catch (e) {
      // Only this attempt's account is removed: `createAccount` succeeded
      // immediately above, so the current session is the one just created.
      var leftOver = false;
      try {
        await gateway.deleteCurrentAccount();
      } catch (_) {
        leftOver = true;
      }
      final base = e is ApiException
          ? 'Your account could not be finished setting up: ${e.message}'
          : 'Your account could not be finished setting up.';
      throw AuthException(
        // If the rollback failed, the user must know an account exists —
        // otherwise "try signing up again" just reports "email already in use".
        leftOver
            ? '$base The sign-in account was created but its profile is '
                'missing; sign in to finish setting it up.'
            : base,
        accountCreated: leftOver,
      );
    }

    // The profile now exists. A failure to read it back is a transient
    // problem, so it must NOT roll back a successfully created account.
    return api.getMyProfile();
  }

  /// Returns the signed-in account's profile, creating it when absent.
  ///
  /// Accounts that predate registration (created by hand in the Firebase
  /// console, or by the old seed script) have an Authentication record and no
  /// `users/{uid}` document. Provisioning gives them a `client` profile, which
  /// is exactly what self-service registration would have produced — it cannot
  /// grant `lawyer` or `admin`, and it cannot touch an existing document.
  Future<AppProfile> loadOrProvisionProfile({String? fallbackName}) async {
    final user = gateway.currentUser;
    if (user == null) throw AuthException('You are not signed in.');

    try {
      return await api.getMyProfile();
    } on ApiException catch (e) {
      if (!e.isNotFound) rethrow; // 401/403/5xx are real problems
    }

    await api.provisionProfile(name: fallbackName ?? defaultName(user));
    return api.getMyProfile();
  }

  /// A name that satisfies the backend's 2-character minimum, derived from the
  /// account when the user has not typed one.
  static String defaultName(AuthUser user) {
    final email = user.emailOrEmpty;
    final at = email.indexOf('@');
    final local = at > 0 ? email.substring(0, at) : email;
    final trimmed = local.trim();
    return trimmed.length >= 2 ? trimmed : 'Client';
  }

  Future<void> signOut() => gateway.signOut();

  /// Changes the password of the signed-in account.
  ///
  /// Deliberately does not touch the backend: the password is Firebase
  /// Authentication's, and no server-side record of it exists.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) =>
      gateway.changePassword(
        currentPassword: currentPassword,
        newPassword: newPassword,
      );

  /// Releases the HTTP client held by [api].
  void dispose() => api.dispose();
}
