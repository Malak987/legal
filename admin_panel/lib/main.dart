import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'config/theme.dart';
import 'providers/auth_provider.dart';
import 'screens/home_shell.dart';
import 'screens/login_screen.dart';
import 'services/auth_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // One Supabase-backed provider owns refresh-token restoration for the panel.
  final authProvider = AuthProvider(AuthService())..bindAuthState();
  unawaited(authProvider.restore());
  runApp(AdminApp(authProvider: authProvider));
}

class AdminApp extends StatelessWidget {
  const AdminApp({super.key, this.authProvider});

  /// Optional pre-built [AuthProvider], used by tests without a live project.
  @visibleForTesting
  final AuthProvider? authProvider;

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => authProvider ?? (AuthProvider(AuthService())..bindAuthState()),
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
    final auth = AuthProvider.watchOf(context);

    switch (auth.status) {
      case AuthStatus.unknown:
        return _SplashGate(
          message: auth.error,
          onRetry: auth.error == null ? null : auth.retry,
        );
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
  const _SplashGate({this.message, this.onRetry});

  final String? message;
  final Future<void> Function()? onRetry;

  @override
  Widget build(BuildContext context) {
    final error = message;
    final retry = onRetry;
    return Scaffold(
      backgroundColor: AppTheme.primary,
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircleAvatar(
                  radius: 42,
                  backgroundColor: Colors.amber,
                  child: Icon(Icons.gavel, color: Colors.white, size: 44),
                ),
                const SizedBox(height: 24),
                if (error == null) ...[
                  const SizedBox(
                    height: 30,
                    width: 30,
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 3,
                    ),
                  ),
                ] else ...[
                  Icon(
                    Icons.cloud_off_outlined,
                    color: Colors.amber.shade200,
                    size: 40,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    error,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const SizedBox(height: 20),
                  OutlinedButton.icon(
                    onPressed: retry == null ? null : () => retry(),
                    icon: const Icon(Icons.refresh, color: Colors.white),
                    label: const Text(
                      'Retry',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
