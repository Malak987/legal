import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/firebase_options.dart';

/// REST API client for the Legal Services backend (Express + Firestore).
///
/// Signs the user in through Firebase Authentication, then attaches the
/// resulting ID token to every request so the backend can authorize it.
class ApiClient {
  ApiClient({String? baseUrl, http.Client? client})
      : baseUrl = baseUrl ?? _defaultBaseUrl,
        _client = client ?? http.Client();

  /// Local backend URL.
  ///
  /// - Android emulator  -> use http://10.0.2.2:5000/api
  /// - iOS simulator     -> use http://localhost:5000/api
  /// - Physical device   -> use your computer's LAN IP, e.g. http://192.168.1.10:5000/api
  static const _defaultBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.0.28:5000/api',
  );

  final String baseUrl;
  final http.Client _client;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  String? _token;

  String? get token => _token;

  // ------------------------------------------------------------------
  //  Authentication
  // ------------------------------------------------------------------

  Future<void> _ensureToken() async {
    final user = _auth.currentUser;
    if (user != null) {
      _token = await user.getIdToken();
    }
  }

  /// Signs a user in and keeps the ID token for later requests.
  Future<void> signIn(String email, String password) async {
    final credential = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    _token = await credential.user?.getIdToken();
  }

  Future<void> signUp(String email, String password) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    _token = await credential.user?.getIdToken();
  }

  Future<void> signOut() async {
    await _auth.signOut();
    _token = null;
  }

  bool get isSignedIn => _auth.currentUser != null;

  // ------------------------------------------------------------------
  //  HTTP helpers
  // ------------------------------------------------------------------

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        if (_token != null) 'Authorization': 'Bearer $_token',
      };

  Uri _uri(String path, [Map<String, String>? query]) {
    final clean = path.startsWith('/') ? path.substring(1) : path;
    return Uri.parse('$baseUrl/$clean')
        .replace(queryParameters: query == null || query.isEmpty ? null : query);
  }

  /// GET helper that returns the `data` payload of a successful response.
  Future<dynamic> get(String path, {Map<String, String>? query}) async {
    await _ensureToken();
    final res = await _client.get(_uri(path, query), headers: _headers);
    return _decode(res);
  }

  Future<dynamic> post(String path, {Object? body}) async {
    await _ensureToken();
    final res = await _client.post(
      _uri(path),
      headers: _headers,
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(res);
  }

  Future<dynamic> put(String path, {Object? body}) async {
    await _ensureToken();
    final res = await _client.put(
      _uri(path),
      headers: _headers,
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(res);
  }

  Future<dynamic> delete(String path) async {
    await _ensureToken();
    final res = await _client.delete(_uri(path), headers: _headers);
    return _decode(res);
  }

  dynamic _decode(http.Response response) {
    final body = response.body.isEmpty ? null : jsonDecode(response.body);

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

  void dispose() => _client.close();
}

class ApiException implements Exception {
  final String message;
  final int statusCode;
  ApiException(this.message, this.statusCode);

  @override
  String toString() => message;
}