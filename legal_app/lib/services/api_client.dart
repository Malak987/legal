import 'dart:async' show TimeoutException;
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:http/http.dart' as http;

import '../models/app_profile.dart';

/// Supplies a Firebase ID token.
///
/// Injected in tests so requests can be exercised without a live Firebase
/// project; production uses the signed-in Firebase user (see `_defaultToken`).
typedef IdTokenProvider = Future<String?> Function();

/// REST client for the Legal Services backend (Express + Firestore).
///
/// Responsibilities, deliberately limited to transport:
///  - resolve the base URL for the current platform (overridable at build time);
///  - attach a **fresh** Firebase ID token to every request, in one place;
///  - unwrap the `{ success, message, data }` envelope;
///  - turn failures into [ApiException] with a message fit to show a user.
///
/// Sign-in, registration and sign-out live in `services/auth_service.dart`,
/// and screen-level data access lives in `services/app_repository.dart`, so no
/// widget needs to know about Firebase or about token lifetime.
class ApiClient {
  ApiClient({
    String? baseUrl,
    http.Client? client,
    IdTokenProvider? idTokenProvider,
    String? Function()? currentUidProvider,
    Duration requestTimeout = defaultRequestTimeout,
  })  : baseUrl = baseUrl ?? defaultBaseUrl,
        _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider,
        _currentUidProvider = currentUidProvider,
        _requestTimeout = requestTimeout;

  /// How long a single HTTP round-trip may take before it is abandoned.
  ///
  /// Without a deadline a request against an unreachable host can stay pending
  /// indefinitely, which leaves sign-in/sign-up screens spinning forever with
  /// no error and no way out. The value is generous enough for a slow mobile
  /// network and short enough that the UI always recovers.
  static const Duration defaultRequestTimeout = Duration(seconds: 20);

  /// Base URL of the backend API.
  ///
  /// `--dart-define=API_BASE_URL=...` always wins, so any build can point at a
  /// deployed backend without touching code:
  ///
  ///     flutter run --dart-define=API_BASE_URL=http://192.168.1.10:5000/api
  ///
  /// Without it, the default follows the platform, because no single address
  /// is correct everywhere:
  ///
  /// - **Android emulator** -> `http://10.0.2.2:5000/api`. `10.0.2.2` is the
  ///   emulator's alias for the host machine's loopback; `localhost` inside the
  ///   emulator is the emulated device itself.
  /// - **Web, Linux/Windows/macOS desktop, iOS simulator** ->
  ///   `http://localhost:5000/api`.
  /// - **Physical Android/iOS device** -> neither default can reach your
  ///   computer. Pass the LAN IP with `--dart-define` (see above), and make
  ///   sure the backend listens on `0.0.0.0` and the firewall allows port 5000.
  static const String configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  /// The platform-aware default, honouring [configuredBaseUrl] first.
  static String get defaultBaseUrl {
    if (configuredBaseUrl.isNotEmpty) return configuredBaseUrl;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:5000/api';
    }
    return 'http://localhost:5000/api';
  }

  final String baseUrl;
  final http.Client _client;
  final IdTokenProvider? _idTokenProvider;
  final String? Function()? _currentUidProvider;
  final Duration _requestTimeout;

  /// Last token this client saw. Diagnostics only — never logged or stored.
  String? _token;

  /// The most recently issued ID token, if any.
  String? get token => _token;

  /// Uid of the signed-in account, or `null` when signed out / unconfigured.
  ///
  /// Comes from the verified Firebase session, never from a request body.
  String? get currentUid {
    final custom = _currentUidProvider;
    if (custom != null) return custom();
    try {
      return FirebaseAuth.instance.currentUser?.uid;
    } catch (_) {
      // `[core/no-app]` when `Firebase.initializeApp` failed (placeholder
      // options on web/iOS). Treated as "not signed in" rather than a crash.
      return null;
    }
  }

  /// Returns a fresh ID token.
  ///
  /// Firebase caches tokens and refreshes them shortly before expiry, so
  /// calling this per request is the correct centralised mechanism: it never
  /// sends a token that has already expired. `force` is used only to recover
  /// from a 401.
  Future<String?> _freshToken({bool force = false}) async {
    final custom = _idTokenProvider;
    if (custom != null) {
      try {
        final supplied = await custom();
        _token = supplied;
        return supplied;
      } catch (_) {
        return _token;
      }
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return null;
      final fresh = await user.getIdToken(force);
      _token = fresh;
      return fresh;
    } catch (_) {
      // Keep whatever was last known rather than dropping authentication.
      return _token;
    }
  }

  Future<Map<String, String>> _headers({bool forceToken = false}) async {
    final token = await _freshToken(force: forceToken);
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$baseUrl/$clean')
        .replace(queryParameters: query == null || query.isEmpty ? null : query);
  }

  // ------------------------------------------------------------------
  //  Verbs
  // ------------------------------------------------------------------

  Future<dynamic> get(String path, {Map<String, String>? query}) =>
      _send('GET', path, query: query);

  Future<dynamic> post(String path, {Object? body}) =>
      _send('POST', path, body: body);

  Future<dynamic> put(String path, {Object? body}) =>
      _send('PUT', path, body: body);

  Future<dynamic> delete(String path) => _send('DELETE', path);

  Future<http.Response> _perform(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool forceToken = false,
  }) async {
    final headers = await _headers(forceToken: forceToken);
    final uri = _uri(path, query);
    final encoded = body == null ? null : jsonEncode(body);

    Future<http.Response> call() {
      switch (method) {
        case 'POST':
          return _client.post(uri, headers: headers, body: encoded);
        case 'PUT':
          return _client.put(uri, headers: headers, body: encoded);
        case 'DELETE':
          return _client.delete(uri, headers: headers);
        case 'GET':
        default:
          return _client.get(uri, headers: headers);
      }
    }

    try {
      // A deadline on the round-trip, not on the whole retry sequence: each
      // attempt gets its own budget.
      return await call().timeout(_requestTimeout);
    } on TimeoutException {
      // statusCode 0 marks a client-side failure; the message is user-facing.
      throw ApiException(
        'The server took too long to respond. Please check your connection '
        'and try again.',
        0,
      );
    }
  }

  /// Performs the request, retrying **once** with a forced token refresh on
  /// 401 — the case a cached token was revoked or expired mid-session.
  Future<dynamic> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    var response = await _perform(method, path, query: query, body: body);

    // One retry, after forcing a token refresh. The retry is not a loop: a
    // second 401 means the session really is invalid (the interceptor is
    // rejected or the account is disabled), and that must surface as an error.
    if (response.statusCode == 401) {
      response = await _perform(
        method,
        path,
        query: query,
        body: body,
        forceToken: true,
      );
    }

    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    dynamic body;
    if (response.body.isNotEmpty) {
      try {
        body = jsonDecode(response.body);
      } catch (_) {
        // A proxy or crash page returned non-JSON: report the status instead
        // of throwing a FormatException the UI cannot explain.
        throw ApiException(
          'The server returned an unexpected response '
          '(${response.statusCode}).',
          response.statusCode,
        );
      }
    }

    if (response.statusCode >= 200 && response.statusCode < 300) {
      // Unwrap the standard { success, message, data } envelope.
      if (body is Map && body.containsKey('data')) return body['data'];
      return body;
    }

    final message = (body is Map && body['message'] != null)
        ? body['message'].toString()
        : 'Request failed (${response.statusCode})';
    throw ApiException(message, response.statusCode);
  }

  // ------------------------------------------------------------------
  //  Profile
  // ------------------------------------------------------------------

  /// Reads the signed-in account's own profile from `users/{uid}`.
  ///
  /// Typed and defensive: `AppProfile.fromJson` tolerates missing or legacy
  /// fields. Throws [ApiException] with `statusCode == 404` when the account
  /// has no profile document yet (see `AuthService.loadOrProvisionProfile`).
  Future<AppProfile> getMyProfile() async {
    final uid = currentUid;
    if (uid == null || uid.isEmpty) {
      throw ApiException('You are not signed in.', 401);
    }
    final profile = await getProfile(uid);

    // Defence in depth: the backend already scopes `GET /users/:id` to the
    // caller, but a document that does not carry this session's uid means the
    // response is not the profile that was asked for. Treating it as valid
    // would let a misrouted or cached response stand in for authentication.
    if (profile.uid != uid) {
      throw ApiException('Unexpected profile response.', 0);
    }
    return profile;
  }

  /// Reads `users/{uid}`. `uid` must be the caller's own id or an admin must
  /// be the caller — the backend enforces both.
  Future<AppProfile> getProfile(String uid) async {
    final data = await get('users/$uid');
    if (data is! Map) {
      throw ApiException('Unexpected profile response.', 0);
    }
    return AppProfile.fromJson(Map<String, dynamic>.from(data));
  }

  /// Creates the caller's own `users/{uid}` profile with the server-assigned
  /// `client` role (`POST /api/users/me`).
  ///
  /// No uid and no role are sent: the backend takes both from the verified ID
  /// token, and its schema strips a `role` field. A 409 means the
  /// profile already exists, which is treated as success and read back — that
  /// is what makes a retry after a partial failure safe.
  Future<AppProfile> provisionProfile({required String name}) async {
    try {
      final data = await post('users/me', body: {'name': name.trim()});
      if (data is Map) {
        return AppProfile.fromJson(Map<String, dynamic>.from(data));
      }
      return await getMyProfile();
    } on ApiException catch (e) {
      if (e.isConflict) return getMyProfile();
      rethrow;
    }
  }

  /// Updates the caller's own profile (`PUT /api/users/:id`, self-allowed).
  ///
  /// `role` is never sent: the backend strips it for non-admins, and the app
  /// must not be able to express a role change at all. `email` is sent
  /// unchanged because the schema requires it; the backend rejects a changed
  /// address from a non-admin session.
  Future<AppProfile> updateMyProfile({
    required String name,
    required String email,
    String? phone,
    String? address,
    String? avatar,
  }) async {
    final uid = currentUid;
    if (uid == null) {
      throw ApiException('You are not signed in.', 401);
    }
    final data = await put('users/$uid', body: {
      'name': name.trim(),
      'email': email.trim(),
      if (phone != null) 'phone': phone.trim(),
      if (address != null) 'address': address.trim(),
      if (avatar != null) 'avatar': avatar.trim(),
    });
    if (data is Map) {
      return AppProfile.fromJson(Map<String, dynamic>.from(data));
    }
    return getMyProfile();
  }

  void dispose() => _client.close();
}

/// A failed API call.
///
/// [statusCode] is 0 for client-side failures (unexpected payload), so callers
/// can distinguish "the server said no" from "we could not understand it".
class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;

  /// True when retrying later could plausibly succeed.
  bool get isTransient => statusCode == 0 || statusCode >= 500;

  @override
  String toString() => message;
}
