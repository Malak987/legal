import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/supabase_client_config.dart';
import '../config/supabase_config.dart';
import '../models/app_profile.dart';
import 'api_client.dart';

/// The signed-in Supabase Auth account. Its UUID is the canonical identity;
/// public profile fields and roles are always loaded from `public.users`.
class AuthUser {
  const AuthUser({required this.uid, this.email});

  final String uid;
  final String? email;

  String get emailOrEmpty => email ?? '';
}

/// A Supabase Auth failure with a safe message suitable for the UI.
class AuthException implements Exception {
  AuthException(this.message, {this.code, this.accountCreated = false});

  final String message;
  final String? code;

  /// The Auth account was created, but confirmation/profile/session setup is
  /// incomplete. The UI must not suggest that the user register again.
  final bool accountCreated;

  @override
  String toString() => message;
}

/// Secure persistence for the rotating Supabase refresh token.
///
/// Access tokens remain in memory only. Implementations used by tests should be
/// ephemeral; production uses the platform secure-storage/keychain facility.
abstract interface class AuthSessionStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String token);
  Future<void> clear();
}

class SecureAuthSessionStore implements AuthSessionStore {
  SecureAuthSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'legal_supabase_refresh_token_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _key);

  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// Auth operations used by the application/session controller.
abstract interface class AuthGateway {
  /// Emits explicit sign-in/sign-out changes. Implementations do not emit an
  /// initial `null`; startup restoration is performed by [restoreSession].
  Stream<AuthUser?> get authStateChanges;

  AuthUser? get currentUser;

  Future<AuthUser?> restoreSession({Uri? callbackUri});

  Future<AuthUser> signIn({required String email, required String password});

  /// Creates a public client account only. No role is accepted from the caller.
  Future<AuthUser> createAccount({
    required String email,
    required String password,
    String? displayName,
  });

  Future<void> requestPasswordReset({
    required String email,
    String? redirectTo,
  });

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Sets a new password after the Supabase recovery callback has established
  /// a short-lived recovery session.
  Future<void> setPasswordFromRecovery(String newPassword);

  Future<void> signOut();

  bool get isPasswordRecovery;
  void dispose();
}

/// Supabase Auth REST gateway with rotating, securely persisted refresh-token
/// sessions. Only the public anon/publishable key is accepted by this client.
class SupabaseAuthGateway implements AuthGateway {
  /// [config] is the startup-validated configuration shared with [ApiClient].
  /// [supabaseUrl]/[supabaseAnonKey] remain as test overrides.
  SupabaseAuthGateway({
    SupabaseClientConfig? config,
    http.Client? client,
    String? supabaseUrl,
    String? supabaseAnonKey,
    AuthSessionStore? sessionStore,
    String? authRedirectUrl,
    bool? allowClientSignup,
  }) : _client = client ?? http.Client(),
       _allowClientSignup =
           allowClientSignup ?? SupabaseConfig.enableClientSignup,
       _ownsClient = client == null,
       _config = SupabaseClientConfig.select(
         config: config,
         url: supabaseUrl,
         anonKey: supabaseAnonKey,
       ),
       _sessionStore = sessionStore ?? SecureAuthSessionStore(),
       _authRedirectUrl =
           (authRedirectUrl ?? SupabaseConfig.authRedirectUrl).trim();

  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _refreshSkew = Duration(seconds: 60);

  final http.Client _client;
  final bool _allowClientSignup;
  final bool _ownsClient;
  final SupabaseClientConfig _config;
  final AuthSessionStore _sessionStore;
  final String _authRedirectUrl;
  final StreamController<AuthUser?> _authController =
      StreamController<AuthUser?>.broadcast();

  AuthUser? _currentUser;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _accessTokenExpiresAt;
  Future<void>? _refreshInFlight;
  bool _isPasswordRecovery = false;
  bool _disposed = false;

  /// The validated configuration used for every Auth request.
  SupabaseClientConfig get config => _config;

  bool get isConfigured => _config.isValid;

  String get _supabaseUrl => _config.url;
  String get _supabaseAnonKey => _config.anonKey;

  @override
  Stream<AuthUser?> get authStateChanges => _authController.stream;

  @override
  AuthUser? get currentUser => _currentUser;

  @override
  bool get isPasswordRecovery => _isPasswordRecovery;

  /// Current bearer token, refreshed before expiry or on an explicit 401 retry.
  Future<String?> getAccessToken({bool forceRefresh = false}) async {
    final expiresAt = _accessTokenExpiresAt;
    final stillFresh =
        _accessToken != null &&
        (expiresAt == null ||
            DateTime.now().add(_refreshSkew).isBefore(expiresAt));
    if (!forceRefresh && stillFresh) return _accessToken;

    final refreshToken =
        _refreshToken ?? await _sessionStore.readRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return _accessToken;

    try {
      await _refreshSession(refreshToken);
    } on AuthException catch (error) {
      if (_isInvalidRefreshToken(error)) {
        await _clearSession(notify: true);
      }
      // Preserve the last access token on transient network/server errors. The
      // caller's request may still succeed; a 401 retry can force another try.
    } catch (_) {
      // A secure-storage/network plugin error must not crash a widget build.
    }
    return _accessToken;
  }

  @override
  Future<AuthUser?> restoreSession({Uri? callbackUri}) async {
    _ensureConfigured();
    if (callbackUri != null) {
      final callbackUser = await _restoreCallbackSession(callbackUri);
      if (callbackUser != null) return callbackUser;
    }

    if (_currentUser != null) return _currentUser;
    final storedRefreshToken = await _sessionStore.readRefreshToken();
    if (storedRefreshToken == null || storedRefreshToken.isEmpty) return null;

    try {
      await _refreshSession(storedRefreshToken);
      return _currentUser;
    } on AuthException catch (error) {
      if (_isInvalidRefreshToken(error)) {
        await _clearSession(notify: true);
        return null;
      }
      rethrow;
    }
  }

  Future<AuthUser?> _restoreCallbackSession(Uri callbackUri) async {
    if (!_matchesConfiguredRedirect(callbackUri)) return null;
    // Do not let a previously cached recovery flag authorize a malformed or
    // superseding callback while this callback is being validated.
    _isPasswordRecovery = false;

    final callback = <String, String>{...callbackUri.queryParameters};
    if (callbackUri.fragment.isNotEmpty) {
      try {
        callback.addAll(Uri.splitQueryString(callbackUri.fragment));
      } catch (_) {
        throw _invalidRecoveryLink();
      }
    }

    // Supabase returns error details in callback parameters for expired,
    // reused, or otherwise invalid links. Never surface the raw URL or tokens.
    if ((callback['error_code'] ?? callback['error'] ?? '').isNotEmpty) {
      throw _invalidRecoveryLink();
    }

    final accessToken = (callback['access_token'] ?? '').trim();
    final refreshToken = (callback['refresh_token'] ?? '').trim();
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw _invalidRecoveryLink();
    }
    final expiresIn = int.tryParse(callback['expires_in'] ?? '');
    final expiresAt = int.tryParse(callback['expires_at'] ?? '');
    if ((expiresIn != null && expiresIn <= 0) ||
        (expiresAt != null &&
            expiresAt <= DateTime.now().millisecondsSinceEpoch ~/ 1000) ||
        _jwtIsExpired(accessToken)) {
      throw _invalidRecoveryLink();
    }

    final response = await _send(
      'GET',
      _authUri('user'),
      bearerToken: accessToken,
    );
    final decoded = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 400 ||
          response.statusCode == 401 ||
          response.statusCode == 403) {
        throw _invalidRecoveryLink();
      }
      throw _mapSupabaseError(decoded, response.statusCode);
    }

    final type = (callback['type'] ?? '').toLowerCase();
    _isPasswordRecovery = type == 'recovery';
    return _installSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: _extractUser(decoded),
      expiresIn: expiresIn,
      emit: true,
      persistenceRequired: true,
      accountCreated: false,
    );
  }

  bool _matchesConfiguredRedirect(Uri callbackUri) {
    final expected = Uri.tryParse(_authRedirectUrl);
    return expected != null &&
        expected.hasScheme &&
        callbackUri.scheme == expected.scheme &&
        callbackUri.host == expected.host &&
        callbackUri.port == expected.port &&
        callbackUri.path == expected.path;
  }

  bool _jwtIsExpired(String token) {
    final parts = token.split('.');
    if (parts.length != 3) return false;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final exp = (jsonDecode(payload) as Map<String, dynamic>)['exp'];
      final expiry = exp is int ? exp : int.tryParse('$exp');
      return expiry != null &&
          expiry <= DateTime.now().millisecondsSinceEpoch ~/ 1000;
    } catch (_) {
      return false;
    }
  }

  AuthException _invalidRecoveryLink() => AuthException(
    'This password-reset link is invalid or has expired. Request a new link.',
    code: 'invalid-recovery-link',
  );

  @override
  Future<AuthUser> signIn({
    required String email,
    required String password,
  }) async {
    _ensureConfigured();
    final response = await _send(
      'POST',
      _authUri('token', const <String, String>{'grant_type': 'password'}),
      body: <String, dynamic>{'email': email.trim(), 'password': password},
    );
    final decoded = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _mapSupabaseError(decoded, response.statusCode);
    }
    _isPasswordRecovery = false;
    return _installTokenResponse(
      decoded,
      fallbackEmail: email.trim(),
      emit: true,
      persistenceRequired: true,
      accountCreated: false,
    );
  }

  @override
  Future<AuthUser> createAccount({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _ensureConfigured();
    if (!_allowClientSignup) {
      throw AuthException(
        'Client registration is paused until secure profile linking is deployed and verified.',
        code: 'signup-not-enabled',
      );
    }

    final redirect = _authRedirectUrl;
    if (redirect.isEmpty) {
      throw AuthException(
        'Email confirmation is enabled, but this build has no allowed auth redirect. Configure SUPABASE_AUTH_REDIRECT_URL and the project redirect allow-list before registering.',
        code: 'auth-redirect-not-configured',
      );
    }
    final response = await _send(
      'POST',
      _authUri(
        'signup',
        redirect.isEmpty ? null : <String, String>{'redirect_to': redirect},
      ),
      body: <String, dynamic>{
        'email': email.trim(),
        'password': password,
        // This is untrusted profile display data only. The client sends no role;
        // the trusted database Auth lifecycle creates the fixed `client` role.
        'data': <String, dynamic>{
          if (displayName?.trim().isNotEmpty == true)
            'name': displayName!.trim(),
        },
      },
    );
    final decoded = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _mapSupabaseError(decoded, response.statusCode);
    }

    final accessToken = (decoded['access_token'] ?? '').toString().trim();
    final refreshToken = (decoded['refresh_token'] ?? '').toString().trim();
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      // Supabase is configured to require email confirmation. A user object may
      // be returned, but without a session the app must not enter protected UI.
      _currentUser = null;
      _accessToken = null;
      _refreshToken = null;
      _accessTokenExpiresAt = null;
      _isPasswordRecovery = false;
      throw AuthException(
        'Your account was created. Check your email to confirm it, then sign in.',
        code: 'email-confirmation-required',
        accountCreated: true,
      );
    }

    _isPasswordRecovery = false;
    return _installTokenResponse(
      decoded,
      fallbackEmail: email.trim(),
      emit: true,
      persistenceRequired: true,
      accountCreated: true,
    );
  }

  @override
  Future<void> requestPasswordReset({
    required String email,
    String? redirectTo,
  }) async {
    _ensureConfigured();
    final redirect = (redirectTo ?? _authRedirectUrl).trim();
    if (redirect.isEmpty) {
      throw AuthException(
        'Password recovery is not configured for this build. Set SUPABASE_AUTH_REDIRECT_URL and allow it in the Supabase Auth settings.',
        code: 'auth-redirect-not-configured',
      );
    }
    final response = await _send(
      'POST',
      _authUri(
        'recover',
        redirect.isEmpty ? null : <String, String>{'redirect_to': redirect},
      ),
      body: <String, dynamic>{'email': email.trim()},
    );
    final decoded = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _mapSupabaseError(decoded, response.statusCode);
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final user = _currentUser;
    if (user == null) throw AuthException('You are not signed in.');
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw AuthException('This account has no email address.');
    }

    // Supabase Auth does not expose Firebase-style reauthenticate. A fresh
    // password grant is the reauthentication step and rotates this session.
    await signIn(email: email, password: currentPassword);
    await _putPassword(newPassword);
  }

  @override
  Future<void> setPasswordFromRecovery(String newPassword) async {
    if (!_isPasswordRecovery || _currentUser == null) {
      throw AuthException(
        'Open the password-reset link from your email first.',
      );
    }
    await _putPassword(newPassword);
    _isPasswordRecovery = false;
  }

  Future<void> _putPassword(String newPassword) async {
    final token = await getAccessToken();
    if (token == null || token.isEmpty) {
      throw AuthException(
        'Your session expired. Request a new password-reset link.',
      );
    }
    final response = await _send(
      'PUT',
      _authUri('user'),
      bearerToken: token,
      body: <String, dynamic>{'password': newPassword},
    );
    final decoded = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _mapSupabaseError(decoded, response.statusCode);
    }
  }

  Future<AuthUser> _installTokenResponse(
    Map<String, dynamic> response, {
    required String fallbackEmail,
    required bool emit,
    required bool persistenceRequired,
    required bool accountCreated,
  }) async {
    final accessToken = (response['access_token'] ?? '').toString().trim();
    final refreshToken = (response['refresh_token'] ?? '').toString().trim();
    if (accessToken.isEmpty || refreshToken.isEmpty) {
      throw AuthException(
        'Authentication failed: no active session was returned.',
      );
    }
    final user = _extractUser(response, fallbackEmail: fallbackEmail);
    return _installSession(
      accessToken: accessToken,
      refreshToken: refreshToken,
      user: user,
      expiresIn: int.tryParse((response['expires_in'] ?? '').toString()),
      emit: emit,
      persistenceRequired: persistenceRequired,
      accountCreated: accountCreated,
    );
  }

  Future<AuthUser> _installSession({
    required String accessToken,
    required String refreshToken,
    required AuthUser user,
    required bool emit,
    required bool persistenceRequired,
    required bool accountCreated,
    int? expiresIn,
  }) async {
    try {
      await _sessionStore.writeRefreshToken(refreshToken);
    } catch (_) {
      if (persistenceRequired) {
        await _bestEffortLogout(accessToken);
        await _clearSession(notify: false);
        throw AuthException(
          'Could not securely save this session on the device. Please retry.',
          code: 'session-storage-failed',
          accountCreated: accountCreated,
        );
      }
    }

    _accessToken = accessToken;
    _refreshToken = refreshToken;
    _currentUser = user;
    _accessTokenExpiresAt =
        expiresIn == null
            ? null
            : DateTime.now().add(Duration(seconds: expiresIn));
    if (emit && !_authController.isClosed) _authController.add(user);
    return user;
  }

  Future<void> _refreshSession(String refreshToken) {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final pending = _performRefresh(refreshToken);
    _refreshInFlight = pending;
    return pending.whenComplete(() => _refreshInFlight = null);
  }

  Future<void> _performRefresh(String refreshToken) async {
    _ensureConfigured();
    final previousUid = _currentUser?.uid;
    final response = await _send(
      'POST',
      _authUri('token', const <String, String>{'grant_type': 'refresh_token'}),
      body: <String, dynamic>{'refresh_token': refreshToken},
    );
    final decoded = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _mapSupabaseError(decoded, response.statusCode);
    }

    final renewedUser = await _installTokenResponse(
      decoded,
      fallbackEmail: _currentUser?.email ?? '',
      emit: false,
      persistenceRequired: false,
      accountCreated: false,
    );
    // Refreshes must not silently change account identity.
    if (previousUid != null && previousUid != renewedUser.uid) {
      await _clearSession(notify: true);
      throw AuthException(
        'The refreshed session belongs to a different account.',
      );
    }
  }

  Future<http.Response> _send(
    String method,
    Uri uri, {
    Object? body,
    String? bearerToken,
  }) async {
    final request = http.Request(method, uri)
      ..headers.addAll(<String, String>{
        'apikey': _supabaseAnonKey,
        'Content-Type': 'application/json',
        if (bearerToken != null && bearerToken.isNotEmpty)
          'Authorization': 'Bearer $bearerToken',
      });
    if (body != null) request.body = jsonEncode(body);

    try {
      final streamed = await _client.send(request).timeout(_requestTimeout);
      return await http.Response.fromStream(streamed).timeout(_requestTimeout);
    } on TimeoutException {
      throw AuthException(
        'The authentication service took too long to respond. Try again.',
        code: 'network-request-failed',
      );
    } on AuthException {
      rethrow;
    } catch (_) {
      throw AuthException(
        'Network error. Check your connection and try again.',
        code: 'network-request-failed',
      );
    }
  }

  Future<void> _bestEffortLogout(String token) async {
    try {
      await _send('POST', _authUri('logout'), bearerToken: token);
    } catch (_) {}
  }

  Future<void> _clearSession({required bool notify}) async {
    _currentUser = null;
    _accessToken = null;
    _refreshToken = null;
    _accessTokenExpiresAt = null;
    _isPasswordRecovery = false;
    try {
      await _sessionStore.clear();
    } catch (_) {}
    if (notify && !_authController.isClosed) _authController.add(null);
  }

  bool _isInvalidRefreshToken(AuthException error) {
    final code = (error.code ?? '').toLowerCase();
    final message = error.message.toLowerCase();
    return code.contains('invalid_grant') ||
        code.contains('refresh_token_not_found') ||
        message.contains('invalid refresh token') ||
        message.contains('refresh token not found');
  }

  void _ensureConfigured() {
    if (!_config.isValid) {
      throw AuthException(_config.errorMessage, code: 'auth-not-configured');
    }
  }

  Uri _authUri(String path, [Map<String, String>? query]) {
    final base =
        _supabaseUrl.endsWith('/')
            ? _supabaseUrl.substring(0, _supabaseUrl.length - 1)
            : _supabaseUrl;
    final clean = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse(
      '$base/auth/v1/$clean',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
  }

  static Map<String, dynamic> _decodeJson(String raw) {
    if (raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final parsed = jsonDecode(raw);
      if (parsed is Map) return Map<String, dynamic>.from(parsed);
    } catch (_) {}
    return <String, dynamic>{};
  }

  static AuthUser _extractUser(
    Map<String, dynamic> response, {
    String fallbackEmail = '',
  }) {
    final rawUser = response['user'] is Map ? response['user'] : response;
    final user = Map<String, dynamic>.from(rawUser as Map);
    final uid = (user['id'] ?? '').toString().trim();
    if (uid.isEmpty) {
      throw AuthException('Authentication failed: no user id returned.');
    }
    final email = (user['email'] ?? fallbackEmail).toString().trim();
    return AuthUser(uid: uid, email: email.isEmpty ? null : email);
  }

  static AuthException _mapSupabaseError(
    Map<String, dynamic> body,
    int statusCode,
  ) {
    final code =
        (body['error_code'] ?? body['code'] ?? body['error'] ?? '')
            .toString()
            .toLowerCase();
    final message =
        (body['msg'] ?? body['error_description'] ?? body['message'] ?? '')
            .toString();
    final combined = '$code ${message.toLowerCase()}';

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
        'Choose a stronger password (at least 8 characters).',
        code: 'weak-password',
      );
    }
    if (combined.contains('invalid email') ||
        combined.contains('email address is invalid')) {
      return AuthException(
        'Please enter a valid email address.',
        code: 'invalid-email',
      );
    }
    if (combined.contains('refresh token') &&
        (combined.contains('invalid') || combined.contains('not found'))) {
      return AuthException(
        'This session has expired. Please sign in again.',
        code: 'refresh_token_not_found',
      );
    }
    if (statusCode == 429 || combined.contains('over_request_rate_limit')) {
      return AuthException(
        'Too many attempts. Please wait a moment and try again.',
        code: 'too-many-requests',
      );
    }
    if (message.isNotEmpty) {
      return AuthException(message, code: code.isEmpty ? null : code);
    }
    return AuthException(
      'Authentication failed. Please try again.',
      code: code.isEmpty ? null : code,
    );
  }

  @override
  Future<void> signOut() async {
    final token = _accessToken;
    await _clearSession(notify: true);
    if (token != null && token.isNotEmpty && _config.isValid) {
      try {
        await _send('POST', _authUri('logout'), bearerToken: token);
      } catch (_) {
        // Local and secure-storage state is already cleared.
      }
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _authController.close();
    if (_ownsClient) _client.close();
  }
}

/// Supabase-only sign-in, registration and profile loading rules.
class AuthService {
  AuthService({required this.gateway, required this.api});

  final AuthGateway gateway;
  final ApiClient api;

  Stream<AuthUser?> get authStateChanges => gateway.authStateChanges;
  AuthUser? get currentUser => gateway.currentUser;
  bool get isPasswordRecovery => gateway.isPasswordRecovery;

  /// Restores a persisted Supabase session and, when possible, consumes the
  /// callback URI supplied by the web URL or native app-link stream.
  Future<AuthUser?> restoreSession({Uri? callbackUri}) => gateway
      .restoreSession(callbackUri: callbackUri ?? (kIsWeb ? Uri.base : null));

  Future<AppProfile> signIn({
    required String email,
    required String password,
  }) async {
    await gateway.signIn(email: email, password: password);
    return loadProfile();
  }

  /// Creates a public client account only. The role is never supplied by the
  /// UI or Auth user metadata; a trusted server/database flow must provision it.
  Future<AppProfile> register({
    required String name,
    required String email,
    required String password,
  }) async {
    await gateway.createAccount(
      email: email,
      password: password,
      displayName: name.trim(),
    );

    final user = gateway.currentUser;
    if (user == null) {
      throw AuthException(
        'Your account was created. Confirm your email before signing in.',
        code: 'email-confirmation-required',
        accountCreated: true,
      );
    }
    try {
      return await loadProfile();
    } catch (error) {
      final detail =
          error is AuthException || error is ApiException
              ? ' ${error.toString()}'
              : '';
      throw AuthException(
        'Your account was created, but its client profile is not ready.$detail '
        'Retry sign-in later or contact support; do not register again.',
        code: 'profile-provisioning-failed',
        accountCreated: true,
      );
    }
  }

  Future<AppProfile> loadProfile() async {
    if (gateway.currentUser == null) {
      throw AuthException('You are not signed in.');
    }

    late final AppProfile profile;
    try {
      profile = await api.getMyProfile();
    } on ApiException catch (error) {
      if (error.statusCode == 404) {
        await _clearRejectedSession();
        throw AuthException(
          'No application profile is linked to this Auth account. Access is denied; ask support to verify the account.',
          code: 'profile-not-found',
        );
      }
      rethrow;
    }

    if (!profile.hasValidRole || !profile.isClient) {
      await _clearRejectedSession();
      throw AuthException(
        'This app is available to client accounts only.',
        code: 'role-not-authorized',
      );
    }
    if (profile.uid.trim().isEmpty) {
      await _clearRejectedSession();
      throw AuthException(
        'The application profile has no valid identity. Access is denied.',
        code: 'profile-invalid',
      );
    }
    return profile;
  }

  Future<void> _clearRejectedSession() async {
    api.clearApplicationUid();
    try {
      await gateway.signOut();
    } catch (_) {
      // Local Auth state is cleared by the gateway even when logout is offline.
    }
  }

  Future<void> requestPasswordReset(String email) =>
      gateway.requestPasswordReset(email: email);

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => gateway.changePassword(
    currentPassword: currentPassword,
    newPassword: newPassword,
  );

  Future<void> setPasswordFromRecovery(String newPassword) =>
      gateway.setPasswordFromRecovery(newPassword);

  Future<void> signOut() async {
    await gateway.signOut();
    api.clearApplicationUid();
  }

  void dispose() {
    gateway.dispose();
    api.dispose();
  }
}
