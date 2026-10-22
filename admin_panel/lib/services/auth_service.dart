// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'api_service.dart';

/// Holds the signed-in administrator's session.
class AdminSession {
  final String uid;
  final String email;
  final String name;
  final String role;
  final String idToken;

  AdminSession({
    required this.uid,
    required this.email,
    required this.name,
    required this.role,
    required this.idToken,
  });
}

/// The Firestore profile could not be read because of a **transient** problem
/// (network down, offline, permission error, cold cache, ...).
///
/// The session may still be perfectly valid — callers MUST NOT sign the user
/// out when this is thrown. They should surface the message and offer a retry.
class ProfileReadException implements Exception {
  ProfileReadException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => message;
}

/// There is definitively **no** `users/{uid}` document for this account.
///
/// This is a confirmed fact read from the server, so ending the session is
/// safe and correct.
class AdminProfileMissingException implements Exception {
  AdminProfileMissingException(this.uid);

  final String uid;

  @override
  String toString() =>
      'No user profile found for this account (users/$uid). '
      'Ask an administrator to create it, or seed the database.';
}

/// The profile exists but its role is not `admin`.
class NotAdminException implements Exception {
  NotAdminException(this.role);

  final String role;

  @override
  String toString() => 'This account is not an administrator (role: $role).';
}

/// Handles administrator authentication using Supabase Auth (or Firebase
/// Authentication fallback) and verifies the user's authoritative role from
/// the server-side `users` table/collection.
class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFirestore? db,
    ApiService? api,
    http.Client? supabaseHttpClient,
    String? supabaseUrl,
    String? supabaseAnonKey,
  })  : _auth = auth,
        _db = db,
        _api = api ?? ApiService(),
        _supabaseClient = supabaseHttpClient,
        _supabaseUrl = (supabaseUrl ?? AppConfig.supabaseUrl).trim(),
        _supabaseAnonKey =
            (supabaseAnonKey ?? AppConfig.supabaseAnonKey).trim() {
    // Tokens expire after one hour. Give the HTTP client a way to obtain a
    // fresh one for every protected request.
    _api.tokenProvider = freshToken;
  }

  final FirebaseAuth? _auth;
  final FirebaseFirestore? _db;
  final ApiService _api;
  final http.Client? _supabaseClient;
  final String _supabaseUrl;
  final String _supabaseAnonKey;

  AdminSession? _supabaseSession;
  String? _supabaseAccessToken;

  bool get _isSupabaseMode =>
      _supabaseAnonKey.isNotEmpty && _auth == null && _db == null;

  FirebaseAuth get _firebaseAuth => _auth ?? FirebaseAuth.instance;
  FirebaseFirestore get _firestore => _db ?? FirebaseFirestore.instance;
  http.Client get _http => _supabaseClient ?? http.Client();

  ApiService get api => _api;

  /// Auth-state stream. [AuthProvider] subscribes exactly once.
  Stream<User?> get authStateChanges {
    if (_isSupabaseMode) {
      return const Stream<User?>.empty();
    }
    return _firebaseAuth.authStateChanges();
  }

  /// The currently signed-in Firebase user, if any (may be null while the SDK
  /// is still restoring the persisted session on web, or in Supabase mode).
  User? get currentFirebaseUser {
    if (_isSupabaseMode) return null;
    return _firebaseAuth.currentUser;
  }

  /// Returns a valid bearer token, refreshing it when it has expired.
  ///
  /// Falls back to the last known token if a refresh is not possible, so a
  /// transient failure never blanks the Authorization header mid-session.
  Future<String?> freshToken() async {
    if (_isSupabaseMode) {
      return _supabaseAccessToken ?? _api.token;
    }
    final user = _firebaseAuth.currentUser;
    if (user == null) return null;
    try {
      final String? token = await user.getIdToken();
      _api.token = token;
      return token;
    } catch (_) {
      return _api.token;
    }
  }

  /// Signs in with email/password and ensures the account has the admin role.
  Future<AdminSession> signIn(String email, String password) async {
    if (_isSupabaseMode) {
      return _signInWithSupabase(email, password);
    }

    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    final firebaseUser = credential.user;
    if (firebaseUser == null) {
      throw Exception('Sign-in failed: no user returned.');
    }

    final data = await _loadProfileOrEndSession(firebaseUser.uid);
    final role = _roleOf(data);

    if (role != 'admin') {
      await _endSession();
      throw NotAdminException(role);
    }

    final idToken = await firebaseUser.getIdToken();
    _api.token = idToken;

    return AdminSession(
      uid: firebaseUser.uid,
      email: firebaseUser.email ?? email,
      name: data['name']?.toString() ?? firebaseUser.displayName ?? 'Admin',
      role: role,
      idToken: idToken ?? '',
    );
  }

  /// Returns the current administrator (if any) by restoring the token.
  ///
  /// Enforces exactly the same `role == 'admin'` rule as [signIn].
  /// A transient read failure is surfaced as [ProfileReadException] and never
  /// destroys the underlying session.
  Future<AdminSession?> currentUser() async {
    if (_isSupabaseMode) {
      return _supabaseSession;
    }

    final firebaseUser = _firebaseAuth.currentUser;
    if (firebaseUser == null) return null;

    final data = await _loadProfileOrEndSession(firebaseUser.uid);
    final role = _roleOf(data);

    if (role != 'admin') {
      await _endSession();
      throw NotAdminException(role);
    }

    final idToken = await firebaseUser.getIdToken();
    _api.token = idToken;

    return AdminSession(
      uid: firebaseUser.uid,
      email: firebaseUser.email ?? '',
      name: data['name']?.toString() ?? firebaseUser.displayName ?? 'Admin',
      role: role,
      idToken: idToken ?? '',
    );
  }

  Future<void> signOut() async {
    await _endSession();
  }

  // ------------------------------------------------------------------
  //  Internals
  // ------------------------------------------------------------------

  Future<AdminSession> _signInWithSupabase(
    String email,
    String password,
  ) async {
    final base = _supabaseUrl.endsWith('/')
        ? _supabaseUrl.substring(0, _supabaseUrl.length - 1)
        : _supabaseUrl;
    final tokenUri = Uri.parse('$base/auth/v1/token?grant_type=password');

    final response = await _http.post(
      tokenUri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'apikey': _supabaseAnonKey,
      },
      body: jsonEncode(<String, dynamic>{
        'email': email.trim(),
        'password': password,
      }),
    );

    final body = response.body.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(response.body) as Map);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final msg =
          (body['msg'] ?? body['error_description'] ?? body['message'] ?? '')
              .toString();
      throw Exception(msg.isNotEmpty ? msg : 'Invalid email or password.');
    }

    final accessToken = (body['access_token'] ?? '').toString();
    final userMap = body['user'] is Map
        ? Map<String, dynamic>.from(body['user'] as Map)
        : const <String, dynamic>{};
    final authUid = (userMap['id'] ?? '').toString();
    if (authUid.isEmpty || accessToken.isEmpty) {
      throw Exception('Sign-in failed: no user returned.');
    }

    _supabaseAccessToken = accessToken;
    _api.token = accessToken;

    final data = await _loadSupabaseProfileOrEndSession(authUid, accessToken);
    final role = _roleOf(data);

    if (role != 'admin') {
      await _endSession();
      throw NotAdminException(role);
    }

    final resolvedUid = (data['id'] ?? data['uid'] ?? authUid).toString();
    final session = AdminSession(
      uid: resolvedUid,
      email: (data['email'] ?? userMap['email'] ?? email).toString(),
      name: (data['name'] ?? 'Admin').toString(),
      role: role,
      idToken: accessToken,
    );
    _supabaseSession = session;
    return session;
  }

  Future<Map<String, dynamic>> _loadSupabaseProfileOrEndSession(
    String uid,
    String accessToken,
  ) async {
    try {
      return await _readSupabaseProfileFromServer(uid, accessToken);
    } on ProfileReadException {
      rethrow;
    } catch (_) {
      await _endSession();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _readSupabaseProfileFromServer(
    String uid,
    String accessToken,
  ) async {
    final base = _supabaseUrl.endsWith('/')
        ? _supabaseUrl.substring(0, _supabaseUrl.length - 1)
        : _supabaseUrl;
    final uri = Uri.parse('$base/rest/v1/users').replace(
      queryParameters: <String, String>{
        'or': '(id.eq.$uid,auth_user_id.eq.$uid)',
        'select': '*',
        'limit': '1',
      },
    );

    http.Response response;
    try {
      response = await _http.get(
        uri,
        headers: <String, String>{
          'Content-Type': 'application/json',
          'apikey': _supabaseAnonKey,
          'Authorization': 'Bearer $accessToken',
        },
      );
    } catch (e) {
      throw ProfileReadException(
        'Could not read your admin profile from Supabase ($e). '
        'Check your connection, then retry.',
        cause: e,
      );
    }

    if (response.statusCode >= 500 ||
        response.statusCode == 401 ||
        response.statusCode == 403) {
      throw ProfileReadException(
        'Could not read your admin profile from Supabase '
        '(HTTP ${response.statusCode}). Check your connection and RLS policies, then retry.',
      );
    }

    if (response.statusCode == 404) {
      throw AdminProfileMissingException(uid);
    }

    final decoded = response.body.isEmpty ? const <dynamic>[] : jsonDecode(response.body);
    if (decoded is List && decoded.isNotEmpty && decoded.first is Map) {
      return Map<String, dynamic>.from(decoded.first as Map);
    }
    throw AdminProfileMissingException(uid);
  }

  /// Reads `users/{uid}` **from the server** and ends the session only for
  /// definitive outcomes (profile missing). Transient failures are rethrown as
  /// [ProfileReadException] and leave the Firebase session untouched.
  Future<Map<String, dynamic>> _loadProfileOrEndSession(String uid) async {
    Map<String, dynamic> data;
    try {
      data = await _readProfileFromServer(uid);
    } on ProfileReadException {
      rethrow; // transient — keep the session, let the UI retry
    } catch (_) {
      await _endSession(); // definitive — no profile means no admin access
      rethrow;
    }
    return data;
  }

  /// Reads the profile document straight from the server.
  ///
  /// An empty or cold local cache must never be treated as proof that the
  /// profile is missing: on Flutter Web the first read can be served from an
  /// empty cache, which previously caused valid admins to be signed out in a
  /// loop. Requiring `Source.server` makes "missing" a verified fact.
  Future<Map<String, dynamic>> _readProfileFromServer(String uid) async {
    DocumentSnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _firestore
          .collection('users')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
    } on FirebaseException catch (e) {
      throw ProfileReadException(
        'Could not read your admin profile from the server (${e.code}). '
        'Check your connection and your Firestore security rules, then retry.',
        cause: e,
      );
    } catch (e) {
      throw ProfileReadException(
        'Could not read your admin profile from the server ($e). '
        'Check your connection, then retry.',
        cause: e,
      );
    }

    final data = snapshot.data();
    if (!snapshot.exists || data == null) {
      throw AdminProfileMissingException(uid);
    }
    return data;
  }

  static String _roleOf(Map<String, dynamic> data) =>
      (data['role'] ?? 'client').toString();

  /// Ends the active session and clears the API token. Best effort: it must
  /// never prevent the caller from reporting what went wrong.
  Future<void> _endSession() async {
    if (_isSupabaseMode) {
      final token = _supabaseAccessToken;
      _supabaseSession = null;
      _supabaseAccessToken = null;
      _api.token = null;
      if (token != null && token.isNotEmpty) {
        final base = _supabaseUrl.endsWith('/')
            ? _supabaseUrl.substring(0, _supabaseUrl.length - 1)
            : _supabaseUrl;
        try {
          await _http.post(
            Uri.parse('$base/auth/v1/logout'),
            headers: <String, String>{
              'Content-Type': 'application/json',
              'apikey': _supabaseAnonKey,
              'Authorization': 'Bearer $token',
            },
          );
        } catch (_) {}
      }
      return;
    }
    try {
      await _firebaseAuth.signOut();
    } catch (_) {
      // Ignored on purpose — the caller still reports the real reason.
    }
    _api.token = null;
  }
}
