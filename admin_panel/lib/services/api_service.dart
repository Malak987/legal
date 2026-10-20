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
  ApiService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  /// The Firebase ID token, set after a successful sign-in.
  String? token;

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (token != null && token!.isNotEmpty) 'Authorization': 'Bearer $token',
      };

  String get _base => AppConfig.apiBaseUrl;

  // ------------------------------------------------------------------
  //  Low-level helpers
  // ------------------------------------------------------------------

  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    return _request(() => _client.get(_uri(path, query), headers: _headers));
  }

  Future<dynamic> post(String path, {Object? body}) async {
    return _request(
      () => _client.post(
        _uri(path),
        headers: _headers,
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Future<dynamic> put(String path, {Object? body}) async {
    return _request(
      () => _client.put(
        _uri(path),
        headers: _headers,
        body: body == null ? null : jsonEncode(body),
      ),
    );
  }

  Future<dynamic> delete(String path) async {
    return _request(() => _client.delete(_uri(path), headers: _headers));
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
