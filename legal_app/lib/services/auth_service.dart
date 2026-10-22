import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';
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

/// [AuthGateway] backed by Supabase Auth (`/auth/v1/*` GoTrue REST API).
///
/// Uses the public `SUPABASE_ANON_KEY` (never the service-role key) to sign
/// users in, register accounts, refresh JWT access tokens, and update
/// passwords after re-authenticating with the current password.
class SupabaseAuthGateway implements AuthGateway {
  SupabaseAuthGateway({
    http.Client? client,
    String? supabaseUrl,
    String? supabaseAnonKey,
  })  : _client = client ?? http.Client(),
        _supabaseUrl = (supabaseUrl ?? SupabaseConfig.supabaseUrl).trim(),
        _supabaseAnonKey =
            (supabaseAnonKey ?? SupabaseConfig.supabaseAnonKey).trim();

  final http.Client _client;
  final String _supabaseUrl;
  final String _supabaseAnonKey;

  final StreamController<AuthUser?> _authController =
      StreamController<AuthUser?>.broadcast();

  AuthUser? _currentUser;
  String? _accessToken;
  String? _refreshToken;

  /// Current Supabase JWT access token for authenticating backend API calls.
  String? get accessToken => _accessToken;

  /// Returns a valid access token, refreshing via `refresh_token` if needed.
  Future<String?> getAccessToken({bool forceRefresh = false}) async {
    if (forceRefresh && _refreshToken != null && _refreshToken!.isNotEmpty) {
      try {
        await _refreshSession(_refreshToken!);
      } catch (_) {
        // Keep last known token if transient refresh fails.
      }
    }
    return _accessToken;
  }

  @override
  Stream<AuthUser?> get authStateChanges async* {
    yield _currentUser;
    yield* _authController.stream;
  }

  @override
  AuthUser? get currentUser => _currentUser;

  Map<String, String> _headers({String? bearerToken}) => <String, String>{
        'Content-Type': 'application/json',
        'apikey': _supabaseAnonKey,
        if (bearerToken != null && bearerToken.isNotEmpty)
          'Authorization': 'Bearer $bearerToken',
      };

  Uri _authUri(String path, [Map<String, String>? query]) {
    final base = _supabaseUrl.endsWith('/')
        ? _supabaseUrl.substring(0, _supabaseUrl.length - 1)
        : _supabaseUrl;
    final clean = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$base/auth/v1/$clean').replace(
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    _ensureConfigured();
    http.Response response;
    try {
      response = await _client.post(
        _authUri('token', const <String, String>{'grant_type': 'password'}),
        headers: _headers(),
        body: jsonEncode(<String, dynamic>{
          'email': email.trim(),
          'password': password,
        }),
      );
    } catch (_) {
      throw AuthException(
        'Network error. Check your connection and try again.',
        code: 'network-request-failed',
      );
    }

    final decoded = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _mapSupabaseError(decoded, response.statusCode);
    }

    final user = _extractUser(decoded, fallbackEmail: email.trim());
    _accessToken = decoded['access_token']?.toString();
    _refreshToken = decoded['refresh_token']?.toString();
    _currentUser = user;
    _authController.add(user);
    return user;
  }

  @override
  Future<AuthUser> createAccount({
    required String email,
    required String password,
  }) async {
    _ensureConfigured();
    http.Response response;
    try {
      response = await _client.post(
        _authUri('signup'),
        headers: _headers(),
        body: jsonEncode(<String, dynamic>{
          'email': email.trim(),
          'password': password,
        }),
      );
    } catch (_) {
      throw AuthException(
        'Network error. Check your connection and try again.',
        code: 'network-request-failed',
      );
    }

    final decoded = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _mapSupabaseError(decoded, response.statusCode);
    }

    final token = decoded['access_token']?.toString();
    if (token == null || token.isEmpty) {
      // When signup succeeds without returning an immediate session token,
      // sign in with the newly registered credentials.
      return signIn(email: email, password: password);
    }

    final user = _extractUser(decoded, fallbackEmail: email.trim());
    _accessToken = token;
    _refreshToken = decoded['refresh_token']?.toString();
    _currentUser = user;
    _authController.add(user);
    return user;
  }

  @override
  Future<void> deleteCurrentAccount() async {
    await signOut();
  }

  @override
  Future<void> signOut() async {
    final token = _accessToken;
    _currentUser = null;
    _accessToken = null;
    _refreshToken = null;
    _authController.add(null);

    if (token != null && token.isNotEmpty && _supabaseAnonKey.isNotEmpty) {
      try {
        await _client.post(
          _authUri('logout'),
          headers: _headers(bearerToken: token),
        );
      } catch (_) {
        // Local session is already cleared.
      }
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _currentUser;
    if (user == null) {
      throw AuthException('You are not signed in.');
    }
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw AuthException(
        'This account has no email address, so its password cannot be changed here.',
      );
    }

    // Re-authenticate with the current password first.
    await signIn(email: email, password: currentPassword);

    final token = _accessToken;
    if (token == null || token.isEmpty) {
      throw AuthException('Please sign in again to finish this action.');
    }

    http.Response response;
    try {
      response = await _client.put(
        _authUri('user'),
        headers: _headers(bearerToken: token),
        body: jsonEncode(<String, dynamic>{'password': newPassword}),
      );
    } catch (_) {
      throw AuthException(
        'Network error. Check your connection and try again.',
        code: 'network-request-failed',
      );
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final decoded = _decodeJson(response.body);
      throw _mapSupabaseError(decoded, response.statusCode);
    }
  }

  Future<void> _refreshSession(String refreshToken) async {
    final response = await _client.post(
      _authUri(
        'token',
        const <String, String>{'grant_type': 'refresh_token'},
      ),
      headers: _headers(),
      body: jsonEncode(<String, dynamic>{'refresh_token': refreshToken}),
    );
    if (response.statusCode >= 200 && response.statusCode < 300) {
      final decoded = _decodeJson(response.body);
      final nextAccess = decoded['access_token']?.toString();
      final nextRefresh = decoded['refresh_token']?.toString();
      if (nextAccess != null && nextAccess.isNotEmpty) {
        _accessToken = nextAccess;
      }
      if (nextRefresh != null && nextRefresh.isNotEmpty) {
        _refreshToken = nextRefresh;
      }
    }
  }

  void _ensureConfigured() {
    if (_supabaseUrl.isEmpty || _supabaseAnonKey.isEmpty) {
      throw AuthException('Authentication is not configured for this build.');
    }
  }

  static Map<String, dynamic> _decodeJson(String raw) {
    if (raw.trim().isEmpty) return const <String, dynamic>{};
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map) return Map<String, dynamic>.from(parsed);
    } catch (_) {}
    return const <String, dynamic>{};
  }

  static AuthUser _extractUser(
    Map<String, dynamic> decoded, {
    required String fallbackEmail,
  }) {
    final userObj = decoded['user'] is Map
        ? Map<String, dynamic>.from(decoded['user'] as Map)
        : decoded;
    final meta = userObj['user_metadata'] is Map
        ? Map<String, dynamic>.from(userObj['user_metadata'] as Map)
        : const <String, dynamic>{};
    final legacyUid = (meta['legacy_uid'] ?? '').toString().trim();
    final uid = legacyUid.isNotEmpty
        ? legacyUid
        : (userObj['id'] ?? '').toString().trim();
    if (uid.isEmpty) {
      throw AuthException('Authentication failed: no user id returned.');
    }
    final email = (userObj['email'] ?? fallbackEmail).toString().trim();
    return AuthUser(uid: uid, email: email.isEmpty ? null : email);
  }

  static AuthException _mapSupabaseError(
    Map<String, dynamic> body,
    int statusCode,
  ) {
    final rawCode =
        (body['error_code'] ?? body['error'] ?? '').toString().toLowerCase();
    final rawMsg = (body['msg'] ??
            body['error_description'] ??
            body['message'] ??
            '')
        .toString();
    final combined = '$rawCode ${rawMsg.toLowerCase()}';

    if (combined.contains('user_already_exists') ||
        combined.contains('already registered') ||
        combined.contains('already exists')) {
      return AuthException(
        'An account with this email already exists. Try signing in.',
        code: 'email-already-in-use',
      );
    }
    if (combined.contains('invalid_credentials') ||
        combined.contains('invalid login credentials')) {
      return AuthException(
        'Incorrect email or password.',
        code: 'invalid-credential',
      );
    }
    if (combined.contains('weak_password') ||
        combined.contains('password should be at least')) {
      return AuthException(
        'Choose a stronger password (at least 6 characters).',
        code: 'weak-password',
      );
    }
    if (combined.contains(' email') && combined.contains('invalid')) {
      return AuthException(
        'Please enter a valid email address.',
        code: 'invalid-email',
      );
    }
    if (statusCode == 429 || combined.contains('over_request_rate_limit')) {
      return AuthException(
        'Too many attempts. Please wait a moment and try again.',
        code: 'too-many-requests',
      );
    }
    return AuthException(
      rawMsg.isNotEmpty ? rawMsg : 'Authentication failed. Please try again.',
      code: rawCode.isEmpty ? null : rawCode,
    );
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
