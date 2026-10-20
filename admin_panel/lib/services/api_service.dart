import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

/// HTTP client for the backend REST API.
///
/// Responsibilities:
///  - attach the Firebase ID token (Authorization: Bearer ...)
///  - send/receive JSON
///  - normalize errors into [ApiException]
class ApiService {
  ApiService({http.Client? client, this.tokenProvider})
      : _client = client ?? http.Client();

  final http.Client _client;

  /// The Firebase ID token, set after a successful sign-in.
  String? token;

  /// Optional async source for a fresh Firebase ID token.
  ///
  /// Firebase ID tokens expire after one hour. Supplying a provider lets the
  /// client refresh the token before every request instead of sending a stale
  /// one and getting 401 forever.
  final Future<String?> Function()? tokenProvider;

  /// Builds the request headers, refreshing the bearer token when a provider
  /// is available. Falls back to the last known token if a refresh fails.
  Future<Map<String, String>> _headers() async {
    var effective = token;
    final provider = tokenProvider;
    if (provider != null) {
      try {
        final fresh = await provider();
        if (fresh != null && fresh.isNotEmpty) effective = fresh;
      } catch (_) {
        // Keep the last known token rather than dropping authentication.
      }
    }
    return {
      'Content-Type': 'application/json',
      if (effective != null && effective.isNotEmpty)
        'Authorization': 'Bearer $effective',
    };
  }

  String get _base => AppConfig.apiBaseUrl;

  // ------------------------------------------------------------------
  //  Low-level helpers
  // ------------------------------------------------------------------

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    return _request(
      () async => _client.get(_uri(path, query), headers: await _headers()),
    );
  }

  Future<dynamic> post(String path, {Object? body}) async {
    return _request(
      () async => _client.post(
        _uri(path),
        headers: await _headers(),
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Future<dynamic> put(String path, {Object? body}) async {
    return _request(
      () async => _client.put(
        _uri(path),
        headers: await _headers(),
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Future<dynamic> delete(String path) async {
    return _request(
      () async => _client.delete(_uri(path), headers: await _headers()),
    );
  }

  Uri _uri(String path, [Map<String, String>? query]) {
    final cleanPath = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$_base/$cleanPath').replace(
      queryParameters: query == null || query.isEmpty ? null : query,
    );
  }

  Future<dynamic> _request(Future<http.Response> Function() fn) async {
    try {
      final response = await fn();
      return _decode(response);
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException('Network error: $e', 0);
    }
  }

  dynamic _decode(http.Response response) {
    final body = response.body.isEmpty ? null : jsonDecode(response.body);

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return body;
    }

    final message = (body is Map && body['message'] != null)
        ? body['message'].toString()
        : 'Request failed (${response.statusCode})';
    throw ApiException(message, response.statusCode);
  }

  void dispose() => _client.close();
}

/// Thrown for non-2xx responses and network failures.
class ApiException implements Exception {
  final String message;
  final int statusCode;

  ApiException(this.message, this.statusCode);

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;
}
