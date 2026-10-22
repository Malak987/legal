import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_profile.dart';
import '../services/api_client.dart';
import '../services/app_repository.dart';
import '../services/auth_service.dart';

/// Where the app is in the authentication lifecycle.
enum SessionStatus {
  /// Auth state has not been determined yet. Screens must not assume anything.
  resolving,

  /// No Firebase session.
  signedOut,

  /// Signed in **and** the application profile is loaded.
  signedIn,

  /// A Firebase session exists but the profile could not be loaded. Treated as
  /// "not usable yet" so protected screens stay closed.
  profileUnavailable,
}

/// Owns the authentication lifecycle for the whole app.
///
/// One [AuthService.authStateChanges] subscription drives every state change,
/// so the sign-in screen, the drawer and the profile screen all agree. A
/// generation counter discards results from superseded operations, which is
/// what stops a slow profile read from overwriting a newer sign-out.
class SessionController extends ChangeNotifier {
  SessionController({required AuthService auth, AppRepository? repository})
      : _auth = auth,
        _repository = repository;

  final AuthService _auth;
  AppRepository? _repository;

  /// Read access to the backend collections, sharing this session's
  /// [ApiClient] so every request uses the same base URL and token handling.
  AppRepository get repository =>
      _repository ??= AppRepository(_auth.api);

  StreamSubscription<AuthUser?>? _subscription;
  int _generation = 0;

  /// True while [signIn], [register] or [refreshProfile] is running.
  ///
  /// Those methods load the profile themselves, and Firebase also reports the
  /// change on the stream. Without this guard both paths would fetch the
  /// profile — duplicate requests, and a visible flicker.
  bool _explicitOperation = false;

  SessionStatus _status = SessionStatus.resolving;
  AuthUser? _user;
  AppProfile? _profile;
  String? _error;
  bool _busy = false;

  SessionStatus get status => _status;
  AuthUser? get user => _user;
  AppProfile? get profile => _profile;

  /// Last user-facing error, if any. Cleared when a new attempt starts.
  String? get error => _error;

  /// True while a sign-in/registration/refresh is in flight.
  bool get isBusy => _busy;

  /// True only when a profile is loaded. Protected screens gate on this.
  bool get isSignedIn => _status == SessionStatus.signedIn;

  /// True while the app is still deciding. Used to avoid showing either the
  /// signed-in or the signed-out UI too early.
  bool get isResolving => _status == SessionStatus.resolving;

  /// Starts listening for Firebase auth changes. Safe to call more than once.
  void start() {
    if (_subscription != null) return;
    try {
      _subscription = _auth.authStateChanges.listen(
        _onAuthStateChanged,
        onError: (Object error) {
          _status = SessionStatus.signedOut;
          _error = FirebaseAuthGateway.messageForSetupError(error);
          notifyListeners();
        },
      );
    } catch (error) {
      // Firebase is not configured for this build (placeholder options on web
      // or iOS). The app still runs; it just cannot authenticate.
      _status = SessionStatus.signedOut;
      _error = FirebaseAuthGateway.messageForSetupError(error);
      notifyListeners();
    }
  }

  Future<void> _onAuthStateChanged(AuthUser? user) async {
    if (user != null && _explicitOperation) return;
    // The same account reported again (a token refresh, say) must not trigger
    // another profile read.
    if (user != null &&
        _user?.uid == user.uid &&
        _status == SessionStatus.signedIn) {
      return;
    }

    if (user == null) {
      _generation++;
      _user = null;
      _profile = null;
      _error = null;
      _status = SessionStatus.signedOut;
      notifyListeners();
      return;
    }

    final generation = ++_generation;
    _user = user;
    _status = SessionStatus.resolving;
    _error = null;
    notifyListeners();

    try {
      final profile = await _auth.loadOrProvisionProfile();
      if (generation != _generation) return;
      _profile = profile;
      _status = SessionStatus.signedIn;
    } catch (error) {
      if (generation != _generation) return;
      _profile = null;
      _status = SessionStatus.profileUnavailable;
      _error = _describe(error);
    }
    notifyListeners();
  }

  /// Signs in and loads the profile. Returns true when the app is ready.
  Future<bool> signIn({required String email, required String password}) async {
    final generation = ++_generation;
    _explicitOperation = true;
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final profile = await _auth.signIn(email: email, password: password);

      // A newer operation (sign-out, or a second attempt) won while this one
      // was in flight. Reporting success here would let the caller navigate to
      // a protected screen for a session that no longer exists.
      if (generation != _generation) return false;

      _user = _auth.currentUser;
      _profile = profile;
      _status = SessionStatus.signedIn;
      _explicitOperation = false;
      _busy = false;
      notifyListeners();
      return true;
    } catch (error) {
      if (generation != _generation) return false;
      _explicitOperation = false;

      // A profile failure means Firebase did sign the user in, even though
      // this call failed: keep the uid so a retry targets the right account.
      _user ??= _auth.currentUser;
      if (error is AuthException) {
        // The credential was rejected: there is no session to keep.
        _user = null;
        _profile = null;
        _status = SessionStatus.signedOut;
      } else {
        // Signed in, but the profile could not be read. Keep the session and
        // report it, rather than pretending the sign-in failed.
        _status = SessionStatus.profileUnavailable;
      }
      _error = _describe(error);
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  /// Registers a new client. Returns true when the app is ready.
  Future<bool> register({
    required String name,
    required String email,
    required String password,
  }) async {
    final generation = ++_generation;
    _explicitOperation = true;
    _busy = true;
    _error = null;
    notifyListeners();

    try {
      final profile = await _auth.register(
        name: name,
        email: email,
        password: password,
      );

      // Superseded by a newer operation: do not claim the account is ready.
      if (generation != _generation) return false;

      _user = _auth.currentUser;
      _profile = profile;
      _status = SessionStatus.signedIn;
      _explicitOperation = false;
      _busy = false;
      notifyListeners();
      return true;
    } catch (error) {
      if (generation != _generation) return false;
      _explicitOperation = false;

      // A failed registration must not look like a session: the rollback
      // either removed the account or reported that it could not.
      _user = null;
      _profile = null;
      _status = SessionStatus.signedOut;
      _error = _describe(error);
      _busy = false;
      notifyListeners();
      return false;
    }
  }

  /// Re-reads the profile (used by pull-to-refresh and after a transient error).
  Future<void> refreshProfile() async {
    final generation = ++_generation;
    _explicitOperation = true;
    _busy = true;
    notifyListeners();
    try {
      final profile = await _auth.loadOrProvisionProfile();
      if (generation != _generation) return;
      _profile = profile;
      _status = SessionStatus.signedIn;
      _error = null;
    } catch (error) {
      if (generation != _generation) return;
      _status = _user == null
          ? SessionStatus.signedOut
          : SessionStatus.profileUnavailable;
      _error = _describe(error);
    } finally {
      // Only the operation that still owns the state clears the flags; a
      // superseding operation is responsible for its own.
      if (generation == _generation) {
        _explicitOperation = false;
        _busy = false;
        notifyListeners();
      }
    }
  }

  /// Saves the caller's own profile fields and refreshes the cached copy.
  ///
  /// The `role` is never part of this call: it is server-owned, and the backend
  /// strips it from a self-update regardless.
  Future<void> updateProfile({
    required String name,
    required String email,
    String? phone,
    String? address,
  }) async {
    final updated = await _auth.api.updateMyProfile(
      name: name,
      email: email,
      phone: phone,
      address: address,
    );
    // `PUT /api/users/:id` answers with the full stored document, so the
    // response is authoritative for `role` as well. The role is never taken
    // from anything the UI holds — neither promoted nor preserved from a stale
    // cached value. A demotion by an administrator therefore shows up
    // immediately instead of lingering in the UI.
    _profile = AppProfile(
      uid: updated.uid,
      name: updated.name,
      email: updated.email,
      phone: updated.phone,
      role: updated.role,
      avatar: updated.avatar,
      address: updated.address,
    );
    notifyListeners();
  }

  /// Changes the signed-in account's password.
  ///
  /// Throws [AuthException] with a message that can be shown as-is. The session
  /// itself is untouched on success — Firebase re-authenticates the same user,
  /// so the account stays signed in.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    if (!isSignedIn) {
      throw AuthException('You are not signed in.');
    }
    await _auth.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  /// Signs out of Firebase and clears every cached value.
  Future<void> signOut() async {
    _generation++; // discard any in-flight profile read
    _explicitOperation = false;
    try {
      await _auth.signOut();
    } catch (_) {
      // Local state is cleared regardless: the UI must not stay "signed in"
      // because the network was down.
    }
    _user = null;
    _profile = null;
    _error = null;
    _busy = false;
    _status = SessionStatus.signedOut;
    notifyListeners();
  }

  static String _describe(Object error) {
    if (error is AuthException) return error.message;
    if (error is ApiException) {
      if (error.statusCode == 0) {
        // Client-side failure: a timeout or an unusable payload. `ApiClient`
        // already phrased it for the user.
        return error.message;
      }
      if (error.isTransient) {
        return 'Could not reach the server. Check your connection and retry.';
      }
      return error.message;
    }
    return 'Something went wrong. Please try again.';
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _subscription = null;
    // Also closes the shared HTTP client, so a rebuilt app does not leak
    // sockets.
    _auth.dispose();
    super.dispose();
  }
}
