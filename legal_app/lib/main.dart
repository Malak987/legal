import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'config/firebase_options.dart';
import 'constants/colors.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'state/session_controller.dart';
import 'state/session_scope.dart';
import 'views/splash/splashscreen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase so the API layer can authenticate requests.
  // If your firebase_options.dart still has placeholder values this will
  // throw; the app catches it so the UI still loads, and the session reports
  // that authentication is unavailable instead of crashing.
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
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

  SessionController get _session =>
      widget.session ?? _ownedSession ??= _createSession();

  bool get _ownsSession => widget.session == null;

  static SessionController _createSession() {
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
