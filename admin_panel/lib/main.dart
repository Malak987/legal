import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/firebase_options.dart';
import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const AdminApp());
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key, this.authProvider});

  /// Optional pre-built [AuthProvider], used by tests to run the app without
  /// a live Firebase project. When omitted, the real [AuthService] is used and
  /// the persisted session is restored on start.
  @visibleForTesting
  final AuthProvider? authProvider;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => authProvider ?? (AuthProvider(AuthService())..restore()),
      child: MaterialApp(
        title: 'Legal Services Admin',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const AuthGate(),
      ),
    );
  }
}

/// Chooses between the login screen and the admin layout.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    // Listening on purpose: AuthGate must rebuild when the auth status
    // changes so it can swap between splash / login / admin shell.
    final auth = AuthProvider.watchOf(context);

    switch (auth.status) {
      case AuthStatus.unknown:
      case AuthStatus.authenticating:
        return const _SplashGate();
      case AuthStatus.unauthenticated:
        return const LoginScreen();
      case AuthStatus.authenticated:
        return const HomeShell();
    }
  }
}

class _SplashGate extends StatelessWidget {
  const _SplashGate();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            CircleAvatar(
              radius: 42,
              backgroundColor: Colors.amber,
              child: Icon(Icons.gavel, color: Colors.white, size: 44),
            ),
            SizedBox(height: 24),
            SizedBox(
              height: 30,
              width: 30,
              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
            ),
          ],
        ),
      ),
    );
  }
}