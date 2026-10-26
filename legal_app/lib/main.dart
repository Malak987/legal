import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config/supabase_client_config.dart';
import 'constants/colors.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'state/session_controller.dart';
import 'state/session_scope.dart';
import 'views/configuration/supabase_config_error_screen.dart';
import 'views/splash/splashscreen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(bootstrapApp());
}

/// Startup sequence: validate the compiled Supabase configuration first, then
/// build exactly one Supabase session (Auth gateway + data client sharing the
/// same validated config) and start restoring the persisted session.
///
/// With an invalid configuration no Supabase client is created and no network
/// request is made; a configuration screen explains how to rebuild.
Widget bootstrapApp({
  SupabaseClientConfig? config,
  SessionController Function(SupabaseClientConfig config)? createSession,
}) {
  final resolved = config ?? SupabaseClientConfig.environment;
  if (!resolved.isValid) {
    // Safe to log: the message never contains the key value.
    debugPrint(resolved.errorMessage);
    return SupabaseConfigErrorApp(config: resolved);
  }
  final session = (createSession ?? createSupabaseSession)(resolved);
  session.start();
  return MyApp(session: session);
}

/// Wires one [SupabaseAuthGateway] and one [ApiClient] to the same validated
/// [config]. [httpClient] and [sessionStore] are injection points for tests.
SessionController createSupabaseSession(
  SupabaseClientConfig config, {
  http.Client? httpClient,
  AuthSessionStore? sessionStore,
}) {
  final gateway = SupabaseAuthGateway(
    config: config,
    client: httpClient,
    sessionStore: sessionStore,
  );
  final api = ApiClient(
    config: config,
    client: httpClient,
    idTokenProvider: () => gateway.getAccessToken(),
    forceRefreshTokenProvider: () => gateway.getAccessToken(forceRefresh: true),
    currentUidProvider: () => gateway.currentUser?.uid,
  );
  return SessionController(auth: AuthService(gateway: gateway, api: api));
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.session});

  /// Supplied by [bootstrapApp] (already started) or by tests. When omitted
  /// the app builds and starts its own session from the validated config.
  final SessionController? session;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  SessionController? _ownedSession;

  SessionController get _session {
    final injected = widget.session;
    if (injected != null) return injected;
    return _ownedSession ??= _createSession();
  }

  bool get _ownsSession => widget.session == null;

  static SessionController _createSession() =>
      createSupabaseSession(SupabaseClientConfig.environment);

  @override
  void initState() {
    super.initState();
    // Restore the encrypted Supabase refresh-token session before protected
    // screens are selected. Missing public config leaves the user signed out
    // with an actionable auth error rather than falling back to Firebase.
    if (_ownsSession) _session.start();
  }

  @override
  void dispose() {
    if (_ownsSession) _ownedSession?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SessionScope(
      controller: _session,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'Legal Services App',
        theme: ThemeData(
          scaffoldBackgroundColor: AppColors.bgColor,
          useMaterial3: true,
        ),
        home: const SplashScreen(),
      ),
    );
  }
}
