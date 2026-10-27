import 'dart:async';
import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import '../config/supabase_config.dart';
import 'api_service.dart';
import 'auth_callback_url.dart';
import 'recovery_callback.dart';

/// Holds the signed-in internal-panel user's server-verified session.
class AdminSession {
  final String uid;
  final String email;
  final String name;
  final String role;
  final String idToken;

  const AdminSession({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    required this.idToken,
  });
}

class AdminAuthUser {
  const AdminAuthUser({required this.uid, this.email});

  final String uid;
  final String? email;
}

/// Secure persistence for the rotating Supabase refresh token.
abstract interface class AdminSessionStore {
  Future<String?> readRefreshToken();
  Future<void> writeRefreshToken(String token);
  Future<void> clear();
}

class SecureAdminSessionStore implements AdminSessionStore {
  SecureAdminSessionStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  static const String _key = 'legal_admin_supabase_refresh_token_v1';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readRefreshToken() => _storage.read(key: _key);

  @override
  Future<void> writeRefreshToken(String token) =>
      _storage.write(key: _key, value: token);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// A transient Supabase profile/network failure. The refresh-token session is
/// preserved, and the caller should offer a retry instead of signing out.
class ProfileReadException implements Exception {
  ProfileReadException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// There is definitively no application profile linked to this Auth UUID.
class AdminProfileMissingException implements Exception {
  AdminProfileMissingException(this.uid);

  final String uid;

  @override
  String toString() =>
      'No application profile is linked to this Auth account ($uid). Ask an administrator to provision the account.';
}

/// The profile does not have a server-owned role allowed in the internal panel.
class NotAdminException implements Exception {
  NotAdminException(this.role);

  final String role;

  @override
  String toString() =>
      'This account is not authorized for the internal panel (role: $role).';
}

class SupabaseAuthException implements Exception {
  SupabaseAuthException(this.message, {this.code});

  final String message;
  final String? code;

  @override
  String toString() => message;
}

enum RecoveryCallbackStatus { none, ready, invalid, unavailable }

class RecoveryCallbackResult {
  const RecoveryCallbackResult(this.status, {this.message});

  const RecoveryCallbackResult.none() : this(RecoveryCallbackStatus.none);

  const RecoveryCallbackResult.ready() : this(RecoveryCallbackStatus.ready);

  final RecoveryCallbackStatus status;
  final String? message;

  bool get handled => status != RecoveryCallbackStatus.none;
}

/// Supabase Auth-backed internal-panel login and session restoration for the
/// server-provisioned `admin`, `owner`, and read-only `lawyer` roles.
///
/// The app uses the public anon/publishable key and a caller JWT for profile
/// reads. The service-role key is never accepted or embedded in this client.
class AuthService {
  /// Builds the auth service around ONE validated [SupabaseConfig].
  ///
  /// `main()` passes the startup-validated [config]; the same instance is
  /// handed to the [ApiService] created here so sign-in, session restoration
  /// and data requests always use identical project credentials. The
  /// [supabaseUrl]/[supabaseAnonKey] overrides remain for tests.
  factory AuthService({
    SupabaseConfig? config,
    ApiService? api,
    http.Client? supabaseHttpClient,
    String? supabaseUrl,
    String? supabaseAnonKey,
    String? authRedirectUrl,
    AdminSessionStore? sessionStore,
    void Function()? clearCallbackUrl,
  }) {
    final resolved = SupabaseConfig.select(
      config: config,
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    );
    return AuthService._(
      resolved,
      api ?? ApiService(config: resolved),
      supabaseHttpClient: supabaseHttpClient,
      authRedirectUrl: authRedirectUrl,
      sessionStore: sessionStore,
      clearCallbackUrl: clearCallbackUrl,
    );
  }

  AuthService._(
    this._config,
    this._api, {
    http.Client? supabaseHttpClient,
    String? authRedirectUrl,
    AdminSessionStore? sessionStore,
    void Function()? clearCallbackUrl,
  }) : _client = supabaseHttpClient ?? http.Client(),
       _ownsClient = supabaseHttpClient == null,
       _authRedirectUrl = (authRedirectUrl ?? AppConfig.authRedirectUrl).trim(),
       _clearCallbackUrl = clearCallbackUrl ?? clearAuthCallbackFromAddressBar,
       _sessionStore = sessionStore ?? SecureAdminSessionStore() {
    _api.tokenProvider = freshToken;
    _api.forceRefreshTokenProvider = () => freshToken(forceRefresh: true);
  }

  static const Duration _requestTimeout = Duration(seconds: 20);
  static const Duration _refreshSkew = Duration(seconds: 60);

  final ApiService _api;
  final http.Client _client;
  final bool _ownsClient;
  final SupabaseConfig _config;
  final String _authRedirectUrl;
  final AdminSessionStore _sessionStore;
  final void Function() _clearCallbackUrl;
  final StreamController<AdminAuthUser?> _authController =
      StreamController<AdminAuthUser?>.broadcast();

  AdminAuthUser? _authUser;
  String? _accessToken;
  String? _refreshToken;
  DateTime? _accessTokenExpiresAt;
  Future<void>? _refreshInFlight;
  String? _recoveryAccessToken;
  DateTime? _recoveryExpiresAt;
  bool _disposed = false;

  ApiService get api => _api;

  Stream<AdminAuthUser?> get authStateChanges => _authController.stream;

  String get _supabaseUrl => _config.url;
  String get _supabaseAnonKey => _config.anonKey;

  bool get isConfigured => _config.isValid;

  /// Returns a valid Supabase bearer token, refreshing before expiry.
  Future<String?> freshToken({bool forceRefresh = false}) async {
    if (!isConfigured) return _accessToken ?? _api.token;
    final expiry = _accessTokenExpiresAt;
    final isFresh =
        _accessToken != null &&
        (expiry == null || DateTime.now().add(_refreshSkew).isBefore(expiry));
    if (!forceRefresh && isFresh) return _accessToken;

    final refresh = _refreshToken ?? await _sessionStore.readRefreshToken();
    if (refresh == null || refresh.isEmpty) return _accessToken ?? _api.token;
    try {
      await _refresh(refresh);
    } on SupabaseAuthException catch (error) {
      if (_isInvalidRefreshToken(error)) await _clearSession(notify: true);
      // Preserve the current token on temporary connection/server failures.
    } catch (_) {
      // Token refresh is a recovery path and must not crash a widget build.
    }
    return _accessToken ?? _api.token;
  }

  /// Signs in, then verifies the server-owned profile role before granting an
  /// admin, owner, or lawyer panel session. Self-registration is not exposed.
  Future<AdminSession> signIn(String email, String password) async {
    _ensureConfigured();
    final response = await _request(
      'POST',
      _authUri('token', const <String, String>{'grant_type': 'password'}),
      body: <String, dynamic>{'email': email.trim(), 'password': password},
    );
    final decoded = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _authError(decoded, response.statusCode);
    }
    final user = await _installTokenResponse(decoded, email.trim());
    try {
      final session = await _loadAdminSession(user);
      if (!_authController.isClosed) _authController.add(user);
      return session;
    } on AdminProfileMissingException {
      await _clearSession(notify: false);
      rethrow;
    } on NotAdminException {
      await _clearSession(notify: false);
      rethrow;
    }
  }

  /// Consumes an initial Supabase Auth redirect before persisted-session
  /// restoration. Recovery tokens stay in memory only and the browser URL is
  /// scrubbed before any network request is made.
  Future<RecoveryCallbackResult> restoreRecoveryCallback(Uri? uri) async {
    final callback = RecoveryCallback.parse(uri);
    if (!callback.isAuthCallback) return const RecoveryCallbackResult.none();

    try {
      _clearCallbackUrl();
    } catch (_) {
      // Never include the callback URI or tokens in diagnostics.
    }
    _recoveryAccessToken = null;
    _recoveryExpiresAt = null;
    _authUser = null;
    _accessToken = null;
    _refreshToken = null;
    _accessTokenExpiresAt = null;
    _api.token = null;
    try {
      await _sessionStore.clear();
    } catch (_) {}

    if (!callback.isRecovery ||
        callback.hasError ||
        !_matchesAuthRedirect(uri) ||
        callback.accessToken == null ||
        callback.accessToken!.isEmpty) {
      return const RecoveryCallbackResult(
        RecoveryCallbackStatus.invalid,
        message: 'This password-reset link is invalid or expired. Request a new link.',
      );
    }

    final expiresAt = _callbackExpiry(callback, callback.accessToken!);
    if (expiresAt == null || !expiresAt.isAfter(DateTime.now())) {
      return const RecoveryCallbackResult(
        RecoveryCallbackStatus.invalid,
        message: 'This password-reset link is invalid or expired. Request a new link.',
      );
    }

    _recoveryAccessToken = callback.accessToken;
    _recoveryExpiresAt = expiresAt;
    try {
      final response = await _request(
        'GET',
        _authUri('user'),
        bearerToken: callback.accessToken,
      );
      if (response.statusCode >= 200 && response.statusCode < 300) {
        final user = _decodeJson(response.body);
        if ((user['id'] ?? '').toString().trim().isNotEmpty) {
          return const RecoveryCallbackResult.ready();
        }
      }
      _clearRecoveryCredentials();
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode == 400) {
        return const RecoveryCallbackResult(
          RecoveryCallbackStatus.invalid,
          message: 'This password-reset link is invalid or expired. Request a new link.',
        );
      }
      return const RecoveryCallbackResult(
        RecoveryCallbackStatus.unavailable,
        message: 'Could not verify this reset link. Reopen the email link when your connection is available.',
      );
    } on SupabaseAuthException {
      _clearRecoveryCredentials();
      return const RecoveryCallbackResult(
        RecoveryCallbackStatus.unavailable,
        message: 'Could not verify this reset link. Reopen the email link when your connection is available.',
      );
    } catch (_) {
      _clearRecoveryCredentials();
      return const RecoveryCallbackResult(
        RecoveryCallbackStatus.unavailable,
        message: 'Could not verify this reset link. Reopen the email link when your connection is available.',
      );
    }
  }

  /// Updates the password using the short-lived recovery access token. That
  /// token and the companion refresh token are never persisted by this client.
  Future<void> updatePasswordFromRecovery(String password) async {
    if (password.length < 8) {
      throw SupabaseAuthException(
        'Use at least 8 characters for the new password.',
      );
    }
    final token = _recoveryAccessToken;
    final expiry = _recoveryExpiresAt;
    if (token == null || expiry == null || !expiry.isAfter(DateTime.now())) {
      _clearRecoveryCredentials();
      throw SupabaseAuthException(
        'This password-reset link is invalid or expired. Request a new link.',
        code: 'recovery-link-invalid',
      );
    }

    final response = await _request(
      'PUT',
      _authUri('user'),
      bearerToken: token,
      body: <String, dynamic>{'password': password},
    );
    if (response.statusCode == 401 ||
        response.statusCode == 403 ||
        response.statusCode == 400) {
      _clearRecoveryCredentials();
      throw SupabaseAuthException(
        'This password-reset link is invalid or expired. Request a new link.',
        code: 'recovery-link-invalid',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw SupabaseAuthException(
        response.statusCode == 429 ? 'Too many attempts. Wait and try again.' : 'Could not update the password. Try again or request a new reset link.',
        code: response.statusCode == 429
            ? 'too-many-requests'
            : 'recovery-update-failed',
      );
    }

    _clearRecoveryCredentials();
    _authUser = null;
    _accessToken = null;
    _refreshToken = null;
    _accessTokenExpiresAt = null;
    _api.token = null;
    try {
      await _sessionStore.clear();
    } catch (_) {}
  }

  void clearRecoveryState() => _clearRecoveryCredentials();

  void _clearRecoveryCredentials() {
    _recoveryAccessToken = null;
    _recoveryExpiresAt = null;
  }

  bool _matchesAuthRedirect(Uri? incoming) {
    final expected = Uri.tryParse(_authRedirectUrl);
    if (incoming == null ||
        expected == null ||
        _authRedirectUrl.isEmpty ||
        expected.hasQuery ||
        expected.hasFragment ||
        expected.userInfo.isNotEmpty) {
      return false;
    }
    String base(Uri value) {
      final path = value.path.isEmpty ? '/' : value.path;
      final port = value.hasPort ? ':${value.port}' : '';
      return '${value.scheme.toLowerCase()}://${value.host.toLowerCase()}$port$path';
    }

    return base(incoming) == base(expected);
  }

  static DateTime? _callbackExpiry(RecoveryCallback callback, String token) {
    final absolute = callback.expiresAt;
    if (absolute != null) {
      return DateTime.fromMillisecondsSinceEpoch(absolute * 1000, isUtc: true);
    }
    final seconds = callback.expiresIn;
    if (seconds != null) {
      return seconds > 0
          ? DateTime.now().add(Duration(seconds: seconds))
          : DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
    }
    final parts = token.split('.');
    if (parts.length != 3) return null;
    try {
      final payload = jsonDecode(
        utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
      );
      final exp = payload is Map
          ? int.tryParse(payload['exp']?.toString() ?? '')
          : null;
      return exp == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(exp * 1000, isUtc: true);
    } catch (_) {
      return null;
    }
  }

  /// Restores a persisted refresh-token session and revalidates the profile's
  /// admin/owner/lawyer role. Missing or disallowed profiles clear the session;
  /// transient profile reads preserve it and remain retryable.
  Future<AdminSession?> currentUser() async {
    _ensureConfigured();
    var user = _authUser;
    if (user == null) {
      final refresh = await _sessionStore.readRefreshToken();
      if (refresh == null || refresh.isEmpty) return null;
      try {
        await _refresh(refresh);
        user = _authUser;
      } on SupabaseAuthException catch (error) {
        if (_isInvalidRefreshToken(error)) {
          await _clearSession(notify: false);
          return null;
        }
        throw ProfileReadException(
          'Could not restore the Supabase session. Check your connection and retry.',
          cause: error,
        );
      } catch (error) {
        throw ProfileReadException(
          'Could not restore the Supabase session. Check your connection and retry.',
          cause: error,
        );
      }
    }
    if (user == null) return null;

    try {
      final session = await _loadAdminSession(user);
      return session;
    } on ProfileReadException {
      rethrow;
    } on AdminProfileMissingException {
      await _clearSession(notify: false);
      rethrow;
    } on NotAdminException {
      await _clearSession(notify: false);
      rethrow;
    }
  }

  /// Sends a reset link only to an explicitly configured, allow-listed redirect.
  Future<void> requestPasswordReset(String email) async {
    _ensureConfigured();
    if (_authRedirectUrl.isEmpty) {
      throw SupabaseAuthException(
        'Password recovery is not configured. Set SUPABASE_AUTH_REDIRECT_URL and add it to the Supabase Auth redirect allow-list.',
        code: 'auth-redirect-not-configured',
      );
    }
    final response = await _request(
      'POST',
      _authUri('recover', <String, String>{'redirect_to': _authRedirectUrl}),
      body: <String, dynamic>{'email': email.trim()},
    );
    final decoded = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _authError(decoded, response.statusCode);
    }
  }

  Future<AdminSession> _loadAdminSession(AdminAuthUser user) async {
    final token = await freshToken();
    if (token == null || token.isEmpty) {
      throw ProfileReadException(
        'Your Supabase session expired. Please sign in again.',
      );
    }
    final profile = await _readSupabaseProfile(user.uid, token);
    final role = (profile['role'] ?? 'client').toString();
    if (role != 'admin' && role != 'owner' && role != 'lawyer') {
      throw NotAdminException(role);
    }
    return AdminSession(
      uid: (profile['id'] ?? user.uid).toString(),
      email: (profile['email'] ?? user.email ?? '').toString(),
      name: (profile['name'] ?? 'Panel user').toString(),
      role: role,
      idToken: token,
    );
  }

  Future<Map<String, dynamic>> _readSupabaseProfile(
    String authUid,
    String accessToken,
  ) async {
    Future<Map<String, dynamic>?> readBy(String column) async {
      final uri = _restUri('users', <String, String>{
        column: 'eq.$authUid',
        'select': 'id,name,email,role',
        'limit': '2',
      });
      http.Response response;
      try {
        response = await _request('GET', uri, bearerToken: accessToken);
      } on SupabaseAuthException catch (error) {
        throw ProfileReadException(
          'Could not read the Supabase profile. Check your connection and RLS policies, then retry.',
          cause: error,
        );
      }
      if (response.statusCode == 401 ||
          response.statusCode == 403 ||
          response.statusCode >= 500) {
        throw ProfileReadException(
          'Could not read the Supabase profile (HTTP ${response.statusCode}). Check your connection and RLS policies, then retry.',
        );
      }
      if (response.statusCode == 404) return null;

      final dynamic decoded;
      try {
        decoded = response.body.isEmpty
            ? const <dynamic>[]
            : jsonDecode(response.body);
      } catch (_) {
        throw ProfileReadException(
          'Supabase returned an invalid profile response.',
        );
      }
      if (decoded is List) {
        if (decoded.length > 1) {
          throw ProfileReadException(
            'More than one Supabase profile matches this Auth identity. Ask an administrator to reconcile the mapping.',
          );
        }
        if (decoded.isNotEmpty && decoded.first is Map) {
          return Map<String, dynamic>.from(decoded.first as Map);
        }
        return null;
      }
      throw ProfileReadException(
        'Supabase returned an invalid profile response.',
      );
    }

    // A trusted auth_user_id mapping wins over a native UUID-shaped profile.
    // Only use id equality when there is no explicit mapping, avoiding an
    // ambiguous OR query whose first row could be an unrelated legacy record.
    final mapped = await readBy('auth_user_id');
    if (mapped != null) return mapped;
    final native = await readBy('id');
    if (native != null) return native;
    throw AdminProfileMissingException(authUid);
  }

  Future<AdminAuthUser> _installTokenResponse(
    Map<String, dynamic> response,
    String fallbackEmail,
  ) async {
    final access = (response['access_token'] ?? '').toString().trim();
    final refresh = (response['refresh_token'] ?? '').toString().trim();
    if (access.isEmpty || refresh.isEmpty) {
      throw SupabaseAuthException(
        'Sign-in failed: no active Supabase session was returned.',
      );
    }
    final rawUser = response['user'] is Map ? response['user'] : response;
    final user = Map<String, dynamic>.from(rawUser as Map);
    final uid = (user['id'] ?? '').toString().trim();
    if (uid.isEmpty) {
      throw SupabaseAuthException('Sign-in failed: no Auth UUID was returned.');
    }

    try {
      await _sessionStore.writeRefreshToken(refresh);
    } catch (_) {
      await _bestEffortLogout(access);
      await _clearSession(notify: false);
      throw SupabaseAuthException(
        'Could not securely save the admin session on this device. Please retry.',
        code: 'session-storage-failed',
      );
    }
    _accessToken = access;
    _refreshToken = refresh;
    _accessTokenExpiresAt = _expiresAt(response['expires_in']);
    _api.token = access;
    _authUser = AdminAuthUser(
      uid: uid,
      email: (user['email'] ?? fallbackEmail).toString(),
    );
    return _authUser!;
  }

  Future<void> _refresh(String refreshToken) {
    final existing = _refreshInFlight;
    if (existing != null) return existing;
    final pending = _performRefresh(refreshToken);
    _refreshInFlight = pending;
    return pending.whenComplete(() => _refreshInFlight = null);
  }

  Future<void> _performRefresh(String refreshToken) async {
    final oldUid = _authUser?.uid;
    final response = await _request(
      'POST',
      _authUri('token', const <String, String>{'grant_type': 'refresh_token'}),
      body: <String, dynamic>{'refresh_token': refreshToken},
    );
    final decoded = _decodeJson(response.body);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _authError(decoded, response.statusCode);
    }
    final user = await _installTokenResponse(decoded, _authUser?.email ?? '');
    if (oldUid != null && oldUid != user.uid) {
      await _clearSession(notify: true);
      throw SupabaseAuthException(
        'The refreshed token belongs to a different account.',
      );
    }
  }

  Future<http.Response> _request(
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
      throw SupabaseAuthException(
        'The Supabase Auth request timed out. Try again.',
        code: 'network-request-failed',
      );
    } on SupabaseAuthException {
      rethrow;
    } catch (_) {
      throw SupabaseAuthException(
        'Could not reach Supabase Auth. Check your connection and try again.',
        code: 'network-request-failed',
      );
    }
  }

  Future<void> _bestEffortLogout(String token) async {
    try {
      await _request('POST', _authUri('logout'), bearerToken: token);
    } catch (_) {}
  }

  Future<void> _clearSession({required bool notify}) async {
    _clearRecoveryCredentials();
    final token = _accessToken;
    _authUser = null;
    _accessToken = null;
    _refreshToken = null;
    _accessTokenExpiresAt = null;
    _api.token = null;
    try {
      await _sessionStore.clear();
    } catch (_) {}
    if (notify && !_authController.isClosed) _authController.add(null);
    if (token != null && token.isNotEmpty && isConfigured) {
      try {
        await _request('POST', _authUri('logout'), bearerToken: token);
      } catch (_) {}
    }
  }

  bool _isInvalidRefreshToken(SupabaseAuthException error) {
    final code = (error.code ?? '').toLowerCase();
    final message = error.message.toLowerCase();
    return code.contains('invalid_grant') ||
        code.contains('refresh_token_not_found') ||
        message.contains('invalid refresh token') ||
        message.contains('refresh token not found');
  }

  void _ensureConfigured() {
    if (!isConfigured) {
      throw SupabaseAuthException(
        _config.errorMessage,
        code: 'auth-not-configured',
      );
    }
  }

  Uri _authUri(String path, [Map<String, String>? query]) =>
      _uri('/auth/v1/$path', query);

  Uri _restUri(String path, Map<String, String> query) =>
      _uri('/rest/v1/$path', query);

  Uri _uri(String path, Map<String, String>? query) {
    final base = _supabaseUrl.endsWith('/')
        ? _supabaseUrl.substring(0, _supabaseUrl.length - 1)
        : _supabaseUrl;
    return Uri.parse(
      '$base$path',
    ).replace(queryParameters: query == null || query.isEmpty ? null : query);
  }

  static DateTime? _expiresAt(Object? raw) {
    final seconds = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    return seconds == null
        ? null
        : DateTime.now().add(Duration(seconds: seconds));
  }

  static Map<String, dynamic> _decodeJson(String raw) {
    if (raw.trim().isEmpty) return <String, dynamic>{};
    try {
      final value = jsonDecode(raw);
      if (value is Map) return Map<String, dynamic>.from(value);
    } catch (_) {}
    return <String, dynamic>{};
  }

  static SupabaseAuthException _authError(
    Map<String, dynamic> body,
    int statusCode,
  ) {
    final code = (body['error_code'] ?? body['code'] ?? body['error'] ?? '')
        .toString()
        .toLowerCase();
    final message =
        (body['msg'] ?? body['error_description'] ?? body['message'] ?? '')
            .toString();
    if (code.contains('invalid_credentials') ||
        message.toLowerCase().contains('invalid login credentials')) {
      return SupabaseAuthException(
        'Incorrect email or password.',
        code: 'invalid-credential',
      );
    }
    if (statusCode == 429) {
      return SupabaseAuthException(
        'Too many attempts. Wait and try again.',
        code: 'too-many-requests',
      );
    }
    if (message.toLowerCase().contains('refresh token')) {
      return SupabaseAuthException(message, code: 'refresh_token_not_found');
    }
    return SupabaseAuthException(
      message.isEmpty ? 'Supabase Auth request failed ($statusCode).' : message,
      code: code.isEmpty ? null : code,
    );
  }

  Future<void> signOut() => _clearSession(notify: true);

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _clearRecoveryCredentials();
    _authController.close();
    if (_ownsClient) _client.close();
  }
}
