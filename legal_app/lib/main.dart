import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'config/firebase_options.dart';
import 'config/supabase_config.dart';
import 'constants/colors.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'state/session_controller.dart';
import 'state/session_scope.dart';
import 'views/splash/splashscreen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // When SUPABASE_ANON_KEY is provided via --dart-define, the app uses
  // SupabaseAuthGateway directly. Otherwise it initializes Firebase as a
  // legacy fallback.
  if (!SupabaseConfig.isConfigured) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('Firebase initialization failed: $e');
    }
  }

  runApp(const MyApp());
}

class MyApp extends StatefulWidget {
  const MyApp({super.key, this.session});

  /// Injected by tests. When omitted the app builds its own session.
  final SessionController? session;

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  SessionController? _ownedSession;

  SessionController get _session {
    // Written as a body, not `a ?? b ??= c`: that chain does not parse (the
    // analyzer reports `missing_assignable_selector`), because `??=` is not
    // valid in the right-hand position of `??` without parentheses.
    final injected = widget.session;
    if (injected != null) return injected;
    return _ownedSession ??= _createSession();
  }

  bool get _ownsSession => widget.session == null;

  static SessionController _createSession() {
    if (SupabaseConfig.isConfigured) {
      final gateway = SupabaseAuthGateway();
      final api = ApiClient(
        idTokenProvider: () => gateway.getAccessToken(),
        currentUidProvider: () => gateway.currentUser?.uid,
      );
      return SessionController(
        auth: AuthService(gateway: gateway, api: api),
      );
    }
    final api = ApiClient();
    return SessionController(
      auth: AuthService(gateway: FirebaseAuthGateway(), api: api),
    );
  }

  @override
  void initState() {
    super.initState();
    // One listener for the whole app, started before the first frame so the
    // splash screen can wait for a definitive answer instead of guessing.
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
