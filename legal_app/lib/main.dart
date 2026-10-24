import 'package:flutter/material.dart';

import 'config/supabase_config.dart';
import 'constants/colors.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'state/session_controller.dart';
import 'state/session_scope.dart';
import 'views/splash/splashscreen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.session});

  /// Injected by tests. When omitted the app builds its own Supabase session.
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

  static SessionController _createSession() {
    final gateway = SupabaseAuthGateway();
    final api = ApiClient(
      idTokenProvider: () => gateway.getAccessToken(),
      forceRefreshTokenProvider: () =>
          gateway.getAccessToken(forceRefresh: true),
      currentUidProvider: () => gateway.currentUser?.uid,
      supabaseUrl: SupabaseConfig.supabaseUrl,
      supabaseAnonKey: SupabaseConfig.supabaseAnonKey,
    );
    return SessionController(
      auth: AuthService(gateway: gateway, api: api),
    );
  }

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
