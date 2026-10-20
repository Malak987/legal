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

  AuthStatus get status => _status;
  AdminSession? get session => _session;
  String? get error => _error;
  bool get isLoading => _loading;
  bool get isAuthenticated => _status == AuthStatus.authenticated;

  ApiService get api => _authService.api;

  /// Convenience accessor for the nearest [AuthProvider] in the tree.
  static AuthProvider of(BuildContext context) =>
      context.watch<AuthProvider>();

  /// Tries to restore a previously signed-in session at app start.
  Future<void> restore() async {
    try {
      _session = await _authService.currentUser();
      _status =
          _session != null ? AuthStatus.authenticated : AuthStatus.unauthenticated;
    } catch (_) {
      _status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<bool> signIn(String email, String password) async {
    _loading = true;
    _error = null;
    _status = AuthStatus.authenticating;
    notifyListeners();

    try {
      _session = await _authService.signIn(email, password);
      _status = AuthStatus.authenticated;
      _loading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = _humanize(e);
      _status = AuthStatus.unauthenticated;
      _loading = false;
      notifyListeners();
      return false;
    }
  }

  Future<void> signOut() async {
    await _authService.signOut();
    _session = null;
    _status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  String _humanize(Object e) {
    final msg = e.toString().replaceFirst('Exception: ', '');
    if (msg.contains('wrong-password') || msg.contains('invalid-credential')) {
      return 'Incorrect email or password.';
    }
    if (msg.contains('user-not-found')) return 'No account found with this email.';
    if (msg.contains('invalid-email')) return 'Please enter a valid email address.';
    if (msg.contains('too-many-requests')) {
      return 'Too many attempts. Please try again later.';
    }
    return msg;
  }
}
