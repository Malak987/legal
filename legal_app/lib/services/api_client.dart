import 'dart:async' show TimeoutException;
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../config/supabase_config.dart';
import '../models/app_profile.dart';
import '../models/paginated_result.dart';

/// Supplies the signed-in Auth access token.
///
/// Injected so requests can be exercised without a live Supabase project;
/// the configured Auth gateway owns refresh behavior.
typedef IdTokenProvider = Future<String?> Function();

/// REST client for the application during the Supabase migration.
///
/// Supabase mode uses authenticated PostgREST for the self-profile and
/// opt-in favorites slices, anonymous PostgREST for public lawyer reads, plus
/// selected Storage and Edge Function calls. Other routes remain on the legacy
/// Express API until individually migrated. It centralizes token handling,
/// response parsing, deadlines, and user-facing [ApiException] errors. Screens access it through
/// `services/app_repository.dart` rather than owning HTTP/auth details.
class ApiClient {
  ApiClient({
    String? baseUrl,
    http.Client? client,
    IdTokenProvider? idTokenProvider,
    IdTokenProvider? forceRefreshTokenProvider,
    String? Function()? currentUidProvider,
    String? supabaseUrl,
    String? supabaseAnonKey,
    bool? enableSupabaseLawyerCatalog,
    bool? enableSupabaseFavorites,
    Duration requestTimeout = defaultRequestTimeout,
  })  : baseUrl = baseUrl ?? defaultBaseUrl,
        _client = client ?? http.Client(),
        _idTokenProvider = idTokenProvider,
        _forceRefreshTokenProvider = forceRefreshTokenProvider,
        _currentUidProvider = currentUidProvider,
        _supabaseUrl = (supabaseUrl ?? SupabaseConfig.supabaseUrl).trim(),
        _supabaseAnonKey =
            (supabaseAnonKey ?? SupabaseConfig.supabaseAnonKey).trim(),
        _enableSupabaseLawyerCatalog = enableSupabaseLawyerCatalog ??
            SupabaseConfig.useSupabaseLawyerCatalog,
        _enableSupabaseFavorites = enableSupabaseFavorites ??
            SupabaseConfig.useSupabaseFavorites,
        _requestTimeout = requestTimeout;

  /// How long a single HTTP round-trip may take before it is abandoned.
  ///
  /// Without a deadline a request against an unreachable host can stay pending
  /// indefinitely, which leaves sign-in/sign-up screens spinning forever with
  /// no error and no way out. The value is generous enough for a slow mobile
  /// network and short enough that the UI always recovers.
  static const Duration defaultRequestTimeout = Duration(seconds: 20);
  static const Duration defaultEdgeFunctionTimeout = Duration(seconds: 120);

  /// Optional Express API URL. The server is Supabase-backed; no Firebase
  /// Hosting/Functions endpoint is used as a fallback.
  static const String configuredBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
  );

  /// Resolves the explicitly configured Supabase-backed Express API URL.
  /// Direct PostgREST/Auth/Edge Function operations do not use this base URL.
  static String resolveBaseUrl({String configured = configuredBaseUrl}) =>
      configured.trim();

  static String get defaultBaseUrl => resolveBaseUrl();

  final String baseUrl;
  final http.Client _client;
  final IdTokenProvider? _idTokenProvider;
  final IdTokenProvider? _forceRefreshTokenProvider;
  final String? Function()? _currentUidProvider;
  final String _supabaseUrl;
  final String _supabaseAnonKey;
  final bool _enableSupabaseLawyerCatalog;
  final bool _enableSupabaseFavorites;
  final Duration _requestTimeout;

  String? _applicationUid;
  String? _applicationAuthUid;
  AppProfile? _lastSupabaseProfile;

  /// Direct Supabase access is available when the public project settings are
  /// present. Individual repositories still choose which operations have been
  /// migrated; all other routes retain their explicit legacy fallback.
  bool get usesSupabase =>
      _supabaseUrl.isNotEmpty && _supabaseAnonKey.isNotEmpty;

  /// The catalogue slice stays on Express unless explicitly opted in at build
  /// time, after the target database's security remediation is approved.
  bool get usesSupabaseLawyerCatalog =>
      usesSupabase && _enableSupabaseLawyerCatalog;

  /// Owner-scoped favorites use PostgREST only after explicit build opt-in.
  bool get usesSupabaseFavorites => usesSupabase && _enableSupabaseFavorites;

  /// Kept as a descriptive alias for the existing profile call sites.
  bool get usesSupabaseProfile => usesSupabase;

  /// Last token this client saw. Diagnostics only — never logged or stored.
  String? _token;

  /// The most recently issued ID token, if any.
  String? get token => _token;

  /// Application user ID after a RLS-scoped profile read, or the signed Auth
  /// UUID before that mapping is loaded. Never taken from a request body.
  String? get currentUid {
    final authUid = _authUid;
    final appUid = _applicationUid;
    if (appUid != null && appUid.isNotEmpty && _applicationAuthUid == authUid) {
      return appUid;
    }
    if (appUid != null) clearApplicationUid();
    return authUid;
  }

  String? get _authUid => _currentUidProvider?.call();

  /// Clears the application-ID mapping when Auth signs out or changes account.
  void clearApplicationUid() {
    _applicationUid = null;
    _applicationAuthUid = null;
    _lastSupabaseProfile = null;
  }

  /// Returns a fresh ID token.
  ///
  /// The configured Auth gateway supplies a current token; a separate forced
  /// refresh provider is used to recover from a 401 where available.
  Future<String?> _freshToken({bool force = false}) async {
    final custom = force ? _forceRefreshTokenProvider ?? _idTokenProvider : _idTokenProvider;
    if (custom != null) {
      try {
        final supplied = await custom();
        _token = supplied;
        return supplied;
      } catch (_) {
        return _token;
      }
    }

    // Supabase mode must receive a token provider from SupabaseAuthGateway.
    // In isolated tests there may be no provider; never consult a legacy SDK.
    return _token;
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
    if (baseUrl.trim().isEmpty) {
      throw ApiException(
        'This API operation is not configured. Set API_BASE_URL to the Supabase-backed server, or use a screen already connected directly to Supabase.',
        503,
      );
    }
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
      throw ApiException.timeout(
        'The server took too long to respond. Please check your connection '
        'and try again.',
      );
    } catch (_) {
      // Different HTTP adapters surface offline/TLS/socket failures using
      // different exception types. They all arise inside this transport call
      // and are normalized to the same typed, retryable API error.
      throw ApiException.network(
        'Could not reach the server. Check your connection and try again.',
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
        throw ApiException.invalidResponse(
          'The server returned an unexpected response '
          '(${response.statusCode}).',
          statusCode: response.statusCode,
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

  Uri _supabaseUsersUri(Map<String, String> query) {
    final base = _supabaseUrl.endsWith('/')
        ? _supabaseUrl.substring(0, _supabaseUrl.length - 1)
        : _supabaseUrl;
    return Uri.parse('$base/rest/v1/users').replace(queryParameters: query);
  }

  Future<dynamic> _supabaseRequest(
    String method,
    Uri uri, {
    Object? body,
    bool returnRepresentation = false,
  }) async {
    if (!usesSupabaseProfile) {
      throw ApiException('Supabase profile access is not configured.', 503);
    }

    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await _freshToken(force: attempt == 1);
      if (token == null || token.isEmpty) {
        throw ApiException('You are not signed in.', 401);
      }
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'apikey': _supabaseAnonKey,
        'Authorization': 'Bearer $token',
        if (returnRepresentation) 'Prefer': 'return=representation',
      };
      final encoded = body == null ? null : jsonEncode(body);
      http.Response response;
      try {
        Future<http.Response> call() {
          switch (method) {
            case 'PATCH':
              return _client.patch(uri, headers: headers, body: encoded);
            case 'POST':
              return _client.post(uri, headers: headers, body: encoded);
            default:
              return _client.get(uri, headers: headers);
          }
        }

        response = await call().timeout(_requestTimeout);
      } on TimeoutException {
        throw ApiException.timeout(
          'Supabase took too long to respond. Please check your connection and try again.',
        );
      } catch (_) {
        throw ApiException.network(
          'Could not reach Supabase. Check your connection and try again.',
        );
      }

      if (response.statusCode == 401 && attempt == 0) continue;
      dynamic decoded;
      if (response.body.isNotEmpty) {
        try {
          decoded = jsonDecode(response.body);
        } catch (_) {
          throw ApiException(
            'Supabase returned an unexpected response (${response.statusCode}).',
            response.statusCode,
          );
        }
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return decoded;
      }
      final message = decoded is Map
          ? (decoded['message'] ?? decoded['msg'] ?? decoded['error_description'])
              ?.toString()
          : null;
      throw ApiException(
        message?.isNotEmpty == true
            ? message!
            : 'Supabase request failed (${response.statusCode}).',
        response.statusCode,
      );
    }
    throw ApiException('Your session has expired. Please sign in again.', 401);
  }

  Future<AppProfile> _readSupabaseProfile(Map<String, String> query) async {
    final data = await _supabaseRequest('GET', _supabaseUsersUri(query));
    if (data is! List || data.isEmpty || data.first is! Map) {
      throw ApiException('No profile is linked to this Auth account yet.', 404);
    }
    final profile = AppProfile.fromJson(Map<String, dynamic>.from(data.first as Map));
    if (profile.uid.isEmpty) {
      throw ApiException('Supabase returned a profile without an application ID.', 0);
    }
    _applicationUid = profile.uid;
    _applicationAuthUid = _authUid;
    _lastSupabaseProfile = profile;
    return profile;
  }

  // ------------------------------------------------------------------
  //  Profile
  // ------------------------------------------------------------------

  /// Reads the signed-in account's own profile.
  ///
  /// Supabase mode queries `public.users` directly with the signed-in JWT and
  /// relies on RLS; the database `id` becomes the application UID, including
  /// for an explicitly linked legacy account. Legacy mode uses the Express API.
  Future<AppProfile> getMyProfile() async {
    if (usesSupabaseProfile) {
      final authUid = _authUid;
      if (authUid == null || authUid.isEmpty) {
        throw ApiException('You are not signed in.', 401);
      }
      // RLS binds the request to auth.uid(). The OR supports native UUID rows
      // and explicitly linked legacy application IDs; only the profile's
      // server-owned `id` becomes the application UID after that scoped read.
      return _readSupabaseProfile(<String, String>{
        'or': '(id.eq.$authUid,auth_user_id.eq.$authUid)',
        'select': 'id,uid,name,email,phone,role,avatar,address',
        'limit': '1',
      });
    }

    final uid = currentUid;
    if (uid == null || uid.isEmpty) {
      throw ApiException('You are not signed in.', 401);
    }
    final profile = await getProfile(uid);

    // Defence in depth: the backend already scopes `GET /users/:id` to the
    // caller, but a document that does not carry this session's uid means the
    // response is not the profile that was asked for.
    if (profile.uid != uid) {
      throw ApiException('Unexpected profile response.', 0);
    }
    return profile;
  }

  /// Reads a profile by application ID. Supabase RLS or the legacy backend
  /// enforces the caller's row scope.
  Future<AppProfile> getProfile(String uid) async {
    if (usesSupabaseProfile) {
      if (uid.trim().isEmpty) throw ApiException('Profile ID is required.', 400);
      return _readSupabaseProfile(<String, String>{
        'id': 'eq.${uid.trim()}',
        'select': 'id,uid,name,email,phone,role,avatar,address',
        'limit': '1',
      });
    }
    final data = await get('users/$uid');
    if (data is! Map) {
      throw ApiException('Unexpected profile response.', 0);
    }
    return AppProfile.fromJson(Map<String, dynamic>.from(data));
  }

  /// Ensures the caller's profile exists.
  ///
  /// Supabase mode only reads: confirmed Auth triggers provision a `client`
  /// profile and direct client INSERT is revoked. Legacy Firebase mode retains
  /// the Express `/users/me` flow.
  Future<AppProfile> provisionProfile({required String name}) async {
    if (usesSupabaseProfile) {
      // Confirmed Auth users are provisioned by the database trigger. Client
      // INSERT is intentionally revoked so signup cannot choose its role.
      return getMyProfile();
    }
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

  /// Updates the caller's own profile.
  ///
  /// Supabase mode PATCHes only the columns granted by RLS and never sends
  /// `role` or `email`; a changed email must use a verified Auth Admin flow.
  /// Legacy Firebase mode uses the existing Express endpoint.
  Future<AppProfile> updateMyProfile({
    required String name,
    required String email,
    String? phone,
    String? address,
    String? avatar,
  }) async {
    if (usesSupabaseProfile) {
      final authUid = _authUid;
      if (authUid == null || authUid.isEmpty) {
        throw ApiException('You are not signed in.', 401);
      }
      if (_applicationAuthUid != authUid) clearApplicationUid();
      final existing = _lastSupabaseProfile ?? await getMyProfile();
      if (email.trim().toLowerCase() != existing.email.trim().toLowerCase()) {
        throw ApiException(
          'Email changes require the verified Supabase Auth email-update flow.',
          403,
        );
      }
      final data = await _supabaseRequest(
        'PATCH',
        _supabaseUsersUri(<String, String>{
          'id': 'eq.${existing.uid}',
          'select': 'id,uid,name,email,phone,role,avatar,address',
        }),
        body: <String, dynamic>{
          'name': name.trim(),
          if (phone != null) 'phone': phone.trim(),
          if (address != null) 'address': address.trim(),
          if (avatar != null) 'avatar': avatar.trim(),
        },
        returnRepresentation: true,
      );
      if (data is! List || data.isEmpty || data.first is! Map) {
        throw ApiException('Profile update returned no row.', 404);
      }
      final profile = AppProfile.fromJson(Map<String, dynamic>.from(data.first as Map));
      _applicationUid = profile.uid;
      _applicationAuthUid = _authUid;
      _lastSupabaseProfile = profile;
      return profile;
    }

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

  Uri _supabaseResourceUri(String resource, {Map<String, String>? query}) {
    final base = _supabaseUrl.endsWith('/')
        ? _supabaseUrl.substring(0, _supabaseUrl.length - 1)
        : _supabaseUrl;
    return Uri.parse('$base/$resource').replace(
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  /// Reads the public lawyer catalogue through PostgREST using only the public
  /// API key. Omitting Authorization deliberately selects the `anon` database
  /// role, so this path exercises the public SELECT grant and RLS policy rather
  /// than relying on a client session or a privileged server credential.
  Future<List<Map<String, dynamic>>> getSupabasePublicLawyers({
    required Map<String, String> query,
  }) async {
    if (!usesSupabase) {
      throw ApiException('Supabase is not configured for this build.', 503);
    }

    final uri = _supabaseResourceUri('rest/v1/lawyers', query: query);
    http.Response response;
    try {
      response = await _client.get(uri, headers: <String, String>{
        'apikey': _supabaseAnonKey,
        'Accept': 'application/json',
      }).timeout(_requestTimeout);
    } on TimeoutException {
      throw ApiException.timeout(
        'Supabase took too long to respond. Please check your connection and try again.',
      );
    } catch (_) {
      throw ApiException.network(
        'Could not reach Supabase. Check your connection and try again.',
      );
    }

    final decoded = _decodeSupabaseResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _supabaseResponseError(response, decoded);
    }
    if (decoded is! List) {
      throw ApiException.invalidResponse(
        'Supabase returned an unexpected lawyer catalogue.',
      );
    }

    final rows = <Map<String, dynamic>>[];
    for (final row in decoded) {
      if (row is! Map) {
        throw ApiException.invalidResponse(
          'Supabase returned an invalid lawyer record.',
        );
      }
      try {
        rows.add(Map<String, dynamic>.from(row));
      } on TypeError {
        throw ApiException.invalidResponse(
          'Supabase returned an invalid lawyer record.',
        );
      }
    }
    return rows;
  }

  /// Reads one public lawyer page and preserves PostgREST's exact row count
  /// when it supplies a `Content-Range` header.
  Future<PaginatedResult<Map<String, dynamic>>> getSupabasePublicLawyerPage({
    required Map<String, String> query,
    required int page,
    required int limit,
  }) async {
    if (!usesSupabase) {
      throw ApiException('Supabase is not configured for this build.', 503);
    }
    if (page < 1 || limit < 1 || limit > 100) {
      throw ApiException('Invalid lawyer page request.', 400);
    }

    final offset = (page - 1) * limit;
    final pageQuery = <String, String>{
      ...query,
      'limit': '$limit',
      'offset': '$offset',
    };
    final uri = _supabaseResourceUri('rest/v1/lawyers', query: pageQuery);
    http.Response response;
    try {
      response = await _client.get(uri, headers: <String, String>{
        'apikey': _supabaseAnonKey,
        'Accept': 'application/json',
        'Prefer': 'count=exact',
      }).timeout(_requestTimeout);
    } on TimeoutException {
      throw ApiException.timeout(
        'Supabase took too long to respond. Please check your connection and try again.',
      );
    } catch (_) {
      throw ApiException.network(
        'Could not reach Supabase. Check your connection and try again.',
      );
    }

    final decoded = _decodeSupabaseResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _supabaseResponseError(response, decoded);
    }
    if (decoded is! List) {
      throw ApiException.invalidResponse(
        'Supabase returned an unexpected lawyer catalogue.',
        statusCode: response.statusCode,
      );
    }

    final rows = <Map<String, dynamic>>[];
    for (final row in decoded) {
      if (row is! Map) {
        throw ApiException.invalidResponse(
          'Supabase returned an invalid lawyer record.',
          statusCode: response.statusCode,
        );
      }
      try {
        rows.add(Map<String, dynamic>.from(row));
      } on TypeError {
        throw ApiException.invalidResponse(
          'Supabase returned an invalid lawyer record.',
          statusCode: response.statusCode,
        );
      }
    }
    if (rows.length > limit) {
      throw ApiException.invalidResponse(
        'Supabase returned more lawyer rows than requested.',
        statusCode: response.statusCode,
      );
    }

    final range = response.headers['content-range'];
    final countMatch = range == null
        ? null
        : RegExp(r'/([0-9]+|\*)\s*$').firstMatch(range);
    final countToken = countMatch?.group(1);
    final exactTotal = countToken == null || countToken == '*'
        ? null
        : int.tryParse(countToken);
    final total = exactTotal ?? offset + rows.length;
    final totalPages = exactTotal == null
        ? page + (rows.length == limit ? 1 : 0)
        : (exactTotal + limit - 1) ~/ limit;
    return PaginatedResult<Map<String, dynamic>>(
      items: rows,
      page: page,
      limit: limit,
      total: total,
      totalPages: totalPages == 0 ? 1 : totalPages,
      hasMore: exactTotal == null
          ? rows.length == limit
          : offset + rows.length < exactTotal,
    );
  }

  Future<http.Response> _supabaseAuthenticatedCall(
    String method,
    Uri uri, {
    required String contentType,
    Object? body,
    Duration? timeout,
    Map<String, String> extraHeaders = const <String, String>{},
  }) async {
    if (!usesSupabaseProfile) {
      throw ApiException('Supabase is not configured for this build.', 503);
    }
    for (var attempt = 0; attempt < 2; attempt++) {
      final token = await _freshToken(force: attempt == 1);
      if (token == null || token.isEmpty) {
        throw ApiException('You are not signed in.', 401);
      }
      final headers = <String, String>{
        'apikey': _supabaseAnonKey,
        'Authorization': 'Bearer $token',
        'Content-Type': contentType,
        ...extraHeaders,
      };
      try {
        Future<http.Response> call() {
          switch (method) {
            case 'GET':
              return _client.get(uri, headers: headers);
            case 'POST':
              return _client.post(uri, headers: headers, body: body);
            case 'DELETE':
              return _client.delete(uri, headers: headers, body: body);
            default:
              throw ApiException('Unsupported Supabase request method.', 405);
          }
        }

        final response = await call().timeout(timeout ?? _requestTimeout);
        if (response.statusCode == 401 && attempt == 0) continue;
        return response;
      } on TimeoutException {
        throw ApiException.timeout(
          'Supabase took too long to respond. Please try again.',
        );
      } on ApiException {
        rethrow;
      } catch (_) {
        throw ApiException.network(
          'Could not reach Supabase. Check your connection and try again.',
        );
      }
    }
    throw ApiException('Your session has expired. Please sign in again.', 401);
  }

  dynamic _decodeSupabaseResponse(http.Response response) {
    if (response.body.trim().isEmpty) return null;
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw ApiException.invalidResponse(
        'Supabase returned an unexpected response (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
  }

  ApiException _supabaseResponseError(http.Response response, dynamic decoded) {
    final message = decoded is Map
        ? (decoded['message'] ?? decoded['msg'] ?? decoded['error_description'] ?? decoded['error'])
            ?.toString()
        : null;
    return ApiException(
      message?.isNotEmpty == true
          ? message!
          : 'Supabase request failed (${response.statusCode}).',
      response.statusCode,
    );
  }

  Future<dynamic> _supabaseAuthenticatedRestRequest(
    String method,
    String resource, {
    required Map<String, String> query,
    Object? body,
    bool returnRepresentation = false,
  }) async {
    if (!RegExp(r'^rest/v1/[A-Za-z0-9_/]+$').hasMatch(resource) ||
        resource.contains('..')) {
      throw ApiException('Invalid Supabase REST resource.', 400);
    }
    final uri = _supabaseResourceUri(resource, query: query);
    final response = await _supabaseAuthenticatedCall(
      method,
      uri,
      contentType: 'application/json',
      body: body == null ? null : jsonEncode(body),
      extraHeaders: <String, String>{
        'Accept': 'application/json',
        if (returnRepresentation) 'Prefer': 'return=representation',
      },
    );
    final decoded = _decodeSupabaseResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _supabaseResponseError(response, decoded);
    }
    return decoded;
  }

  /// Reads an authenticated PostgREST resource with the caller's JWT.
  Future<dynamic> getSupabaseAuthenticatedResource(
    String resource, {
    required Map<String, String> query,
  }) =>
      _supabaseAuthenticatedRestRequest(
        'GET',
        resource,
        query: query,
      );

  /// Invokes a PostgreSQL RPC with the caller's JWT and public API key.
  Future<dynamic> invokeSupabaseRpc(
    String functionName,
    Map<String, dynamic> body,
  ) {
    if (!RegExp(r'^[a-z0-9_]+$').hasMatch(functionName)) {
      throw ApiException('Invalid Supabase RPC name.', 400);
    }
    return _supabaseAuthenticatedRestRequest(
      'POST',
      'rest/v1/rpc/$functionName',
      query: const <String, String>{},
      body: body,
    );
  }

  /// Deletes rows through PostgREST; RLS remains the authorization boundary.
  Future<dynamic> deleteSupabaseAuthenticatedResource(
    String resource, {
    required Map<String, String> query,
    bool returnRepresentation = false,
  }) =>
      _supabaseAuthenticatedRestRequest(
        'DELETE',
        resource,
        query: query,
        returnRepresentation: returnRepresentation,
      );

  Future<String> _requireSupabaseApplicationUid() async {
    if (!usesSupabase) {
      throw ApiException('Supabase is not configured for this build.', 503);
    }
    final authUid = _authUid?.trim();
    if (authUid == null || authUid.isEmpty) {
      throw ApiException('You are not signed in.', 401);
    }
    if (_applicationAuthUid != authUid || _applicationUid == null) {
      clearApplicationUid();
      await getMyProfile();
    }
    final appUid = _applicationUid?.trim();
    if (appUid == null ||
        appUid.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]+$').hasMatch(appUid)) {
      throw ApiException(
        'The signed-in profile ID cannot be used for a Storage path.',
        400,
      );
    }
    return appUid;
  }

  /// Uploads a PDF through the authenticated document-upload Edge Function.
  /// The server revalidates the byte signature and size before its server-only
  /// service-role client writes the object; this app never receives that key.
  Future<String> uploadPrivatePdf(List<int> bytes) async {
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw ApiException('Choose a non-empty PDF that is 10 MiB or smaller.', 413);
    }
    if (bytes.length < 5 ||
        bytes[0] != 0x25 ||
        bytes[1] != 0x50 ||
        bytes[2] != 0x44 ||
        bytes[3] != 0x46 ||
        bytes[4] != 0x2d) {
      throw ApiException('The selected file does not have a valid PDF header.', 415);
    }

    final ownerId = await _requireSupabaseApplicationUid();
    final uri = _supabaseResourceUri('functions/v1/document-upload');
    final response = await _supabaseAuthenticatedCall(
      'POST',
      uri,
      contentType: 'application/pdf',
      body: bytes,
      timeout: defaultEdgeFunctionTimeout,
      extraHeaders: const <String, String>{'Accept': 'application/json'},
    );
    final decoded = _decodeSupabaseResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _supabaseResponseError(response, decoded);
    }
    if (decoded is! Map || decoded['object_path'] is! String) {
      throw ApiException.invalidResponse(
        'The document upload returned an unexpected response.',
        statusCode: response.statusCode,
      );
    }
    final objectPath = decoded['object_path'] as String;
    final segments = objectPath.split('/');
    if (segments.length != 3 ||
        segments[0] != ownerId ||
        segments[1] != 'documents' ||
        !RegExp(r'^[A-Za-z0-9_-]+\.pdf$').hasMatch(segments[2])) {
      throw ApiException.invalidResponse(
        'The document upload returned a path outside this profile.',
        statusCode: response.statusCode,
      );
    }
    return objectPath;
  }

  /// Invokes an authenticated Supabase Edge Function using only the public
  /// anon/publishable key and the current user's JWT.
  Future<Map<String, dynamic>> invokeSupabaseFunction(
    String functionName,
    Map<String, dynamic> body,
  ) async {
    if (!RegExp(r'^[a-z0-9-]+$').hasMatch(functionName)) {
      throw ApiException('Invalid Edge Function name.', 400);
    }
    final uri = _supabaseResourceUri('functions/v1/$functionName');
    final response = await _supabaseAuthenticatedCall(
      'POST',
      uri,
      contentType: 'application/json',
      body: jsonEncode(body),
      timeout: defaultEdgeFunctionTimeout,
    );
    final decoded = _decodeSupabaseResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _supabaseResponseError(response, decoded);
    }
    if (decoded is! Map) {
      throw ApiException('The Edge Function returned an unexpected response.', 0);
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// Best-effort cleanup for a temporary owner-owned PDF. Storage RLS checks
  /// the authenticated user again; callers cannot supply another owner's path.
  Future<void> deletePrivatePdf(String objectPath) async {
    final segments = objectPath.split('/');
    if (segments.length != 3 ||
        segments[1] != 'documents' ||
        !RegExp(r'^[A-Za-z0-9_-]+\.pdf$').hasMatch(segments[2])) {
      throw ApiException('The document path is not owned by this session.', 403);
    }
    final ownerId = await _requireSupabaseApplicationUid();
    if (segments[0] != ownerId) {
      throw ApiException('The document path is not owned by this session.', 403);
    }
    final uri = _supabaseResourceUri('storage/v1/object/legal-documents');
    final response = await _supabaseAuthenticatedCall(
      'DELETE',
      uri,
      contentType: 'application/json',
      body: jsonEncode(<String, dynamic>{'prefixes': <String>[objectPath]}),
    );
    final decoded = _decodeSupabaseResponse(response);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw _supabaseResponseError(response, decoded);
    }
  }

  void dispose() => _client.close();
}

/// Stable categories for failures returned by the API and its transports.
enum ApiErrorKind {
  request,
  network,
  timeout,
  invalidResponse,
  unauthorized,
  forbidden,
  notFound,
  conflict,
  server,
}

/// A failed API call with a stable, typed error category.
///
/// `statusCode == 0` is reserved for client-side failures that do not have an
/// HTTP response. The category distinguishes a transport failure from a bad
/// payload while preserving the legacy status-code helpers used by screens.
class ApiException implements Exception {
  ApiException(this.message, this.statusCode, {ApiErrorKind? kind})
      : kind = kind ?? _kindForStatus(statusCode);

  final String message;
  final int statusCode;
  final ApiErrorKind kind;

  factory ApiException.network(String message) =>
      ApiException(message, 0, kind: ApiErrorKind.network);

  factory ApiException.timeout(String message) =>
      ApiException(message, 0, kind: ApiErrorKind.timeout);

  factory ApiException.invalidResponse(
    String message, {
    int statusCode = 502,
  }) =>
      ApiException(message, statusCode, kind: ApiErrorKind.invalidResponse);

  static ApiErrorKind _kindForStatus(int statusCode) {
    switch (statusCode) {
      case 401:
        return ApiErrorKind.unauthorized;
      case 403:
        return ApiErrorKind.forbidden;
      case 404:
        return ApiErrorKind.notFound;
      case 409:
        return ApiErrorKind.conflict;
      default:
        return statusCode >= 500 ? ApiErrorKind.server : ApiErrorKind.request;
    }
  }

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isConflict => statusCode == 409;
  bool get isNetworkFailure =>
      kind == ApiErrorKind.network || kind == ApiErrorKind.timeout;

  /// True when retrying later could plausibly succeed.
  bool get isTransient =>
      isNetworkFailure || statusCode == 0 || statusCode >= 500;

  @override
  String toString() => message;
}
