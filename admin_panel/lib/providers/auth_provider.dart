import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/api_service.dart';
import '../services/auth_service.dart';

enum AuthStatus { unknown, unauthenticated, authenticating, authenticated }

/// Exposes authentication state to the UI.
class AuthProvider extends ChangeNotifier {
  AuthProvider(this._authService);

  final AuthService _authService;

  AuthStatus _status = AuthStatus.unknown;
  AdminSession? _session;
  String? _error;
  bool _loading = false;

  /// Monotonic counter guarding every async state write.
  ///
  /// `restore()` can make a network request that takes seconds on a cold
  /// start. Without this guard, a slow `restore()` finishing *after* a
  /// successful `signIn()` would overwrite `authenticated` with
  /// `unauthenticated` and bounce the user back to the login screen — the
  /// redirect loop. Every new operation bumps the counter, and a stale
  /// operation checks it before writing.
  int _generation = 0;

  /// The single Supabase auth-state subscription (null until bound).
  StreamSubscription<AdminAuthUser?>? _authSub;

  AuthStatus get status => _status;
  AdminSession? get session => _session;
  String? get error => _error;
  bool get isLoading => _loading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  ApiService get api => _authService.api;

  /// Non-listening accessor for the nearest [AuthProvider] in the tree.
  ///
  /// Use this from event handlers (`onPressed`, `onTap`), `initState`,
  /// `_fetch`-style async methods, and anywhere else that is **not** the
  /// `build()` method. It does not register a rebuild dependency, so it is
  /// safe outside the widget tree (e.g. from a button callback).
  static AuthProvider of(BuildContext context) =>
      context.read<AuthProvider>();

  /// Listening accessor for the nearest [AuthProvider] in the tree.
  ///
  /// **Only** call this from `build()`. It registers a rebuild dependency so
  /// the widget rebuilds whenever [status], [isLoading] or [error] change.
  /// Calling it from an event handler throws a [FlutterError].
  static AuthProvider watchOf(BuildContext context) =>
      context.watch<AuthProvider>();

  /// Subscribes to explicit Supabase Auth sign-out/session invalidation.
  ///
  /// Idempotent: calling it more than once never creates a second
  /// subscription, so session restoration cannot be triggered repeatedly.
  void bindAuthState() {
    if (_authSub != null) return;

    _authSub = _authService.authStateChanges.listen((user) {
      if (user == null) {
        // Explicit sign-out or a revoked/invalid refresh token. Successful
        // sign-in is finalized by signIn() after its profile role is checked.
        _applySignedOut('Your session has ended. Please sign in again.');
      }
    });
  }

  void _applySignedOut(String? message) {
    _generation++; // invalidate anything still in flight
    _session = null;
    _status = AuthStatus.unauthenticated;
    _loading = false;
    if (message != null) _error = message;
    notifyListeners();
  }

  bool _isCurrent(int generation) => generation == _generation;

  /// Tries to restore a previously signed-in session at app start.
  ///
  /// Safe to call more than once: it returns immediately when a verified
  /// admin session is already held.
  Future<void> restore() async {
    if (_status == AuthStatus.authenticated && _session != null) return;

    final generation = ++_generation;

    // Deliberately does NOT touch _loading: `AuthStatus.unknown` already
    // renders the splash gate, and flipping _loading here would make the
    // double-submit guard in signIn() reject a legitimate sign-in that
    // happens while restoration is still in flight.
    try {
      final session = await _authService.currentUser();
      if (!_isCurrent(generation)) return; // superseded by signIn/signOut

      _session = session;
      _status = session != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated;
      _error = null;
    } on ProfileReadException catch (e) {
      if (!_isCurrent(generation)) return;

      // Transient: the Supabase refresh-token session is still valid; do NOT sign out
      // and do NOT fall back to the login screen. Stay put and let the user
      // retry with an actionable message.
      _session = null;
      _status = AuthStatus.unknown;
      _error = e.message;
    } catch (e) {
      if (!_isCurrent(generation)) return;

      // Confirmed rejection (missing profile / not an admin). AuthService
      // has already cleared the persisted Supabase session.
      _session = null;
      _status = AuthStatus.unauthenticated;
      _error = _humanize(e);
    }

    _loading = false;
    notifyListeners();
  }

  /// Re-runs [restore()] after a transient failure.
  Future<void> retry() => restore();

  Future<bool> signIn(String email, String password) async {
    if (_loading) return false; // ignore double submits

    final generation = ++_generation;
    _loading = true;
    _error = null;
    _status = AuthStatus.authenticating;
    notifyListeners();

    try {
      final session = await _authService.signIn(email, password);
      if (!_isCurrent(generation)) return false;

      _session = session;
      _status = AuthStatus.authenticated;
      _error = null;
    } on ProfileReadException catch (e) {
      if (!_isCurrent(generation)) return false;

      // Credentials were accepted but the profile could not be verified.
      // Preserve the encrypted Supabase session and let the user retry.
      _session = null;
      _status = AuthStatus.unknown;
      _error = e.message;
    } catch (e) {
      if (!_isCurrent(generation)) return false;

      _session = null;
      _status = AuthStatus.unauthenticated;
      _error = _humanize(e);
    }

    _loading = false;
    notifyListeners();
    return _status == AuthStatus.authenticated;
  }

  Future<void> requestPasswordReset(String email) =>
      _authService.requestPasswordReset(email);

  Future<void> signOut() async {
    _generation++; // discard any in-flight restore/signIn
    try {
      await _authService.signOut();
    } catch (_) {
      // Still clear local state even if the network call failed.
    }
    _session = null;
    _status = AuthStatus.unauthenticated;
    _loading = false;
    _error = null;
    notifyListeners();
  }

  String _humanize(Object e) {
    if (e is NotAdminException) return e.toString();
    if (e is AdminProfileMissingException) return e.toString();
    if (e is ProfileReadException) return e.message;

    final msg = e.toString().replaceFirst('Exception: ', '');
    if (msg.contains('wrong-password') || msg.contains('invalid-credential')) {
      return 'Incorrect email or password.';
    }
    if (msg.contains('user-not-found')) return 'No account found with this email.';
    if (msg.contains('invalid-email')) return 'Please enter a valid email address.';
    if (msg.contains('too-many-requests')) {
      return 'Too many attempts. Please try again later.';
    }
    if (msg.contains('network-request-failed') || msg.contains('network')) {
      return 'Network error. Check your connection and try again.';
    }
    return msg;
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _authSub = null;
    _authService.dispose();
    super.dispose();
  }
}
