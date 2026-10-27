import 'package:flutter/material.dart';

import '../config/theme.dart';
import '../providers/auth_provider.dart';

class PasswordRecoveryScreen extends StatefulWidget {
  const PasswordRecoveryScreen({super.key});

  @override
  State<PasswordRecoveryScreen> createState() => _PasswordRecoveryScreenState();
}

class _PasswordRecoveryScreenState extends State<PasswordRecoveryScreen> {
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  String? _formError;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _update() async {
    final value = _password.text;
    if (value.length < 8) {
      setState(
        () => _formError = 'Use at least 8 characters for the new password.',
      );
      return;
    }
    if (value != _confirm.text) {
      setState(() => _formError = 'The passwords do not match.');
      return;
    }
    setState(() => _formError = null);
    await AuthProvider.of(context).updatePasswordFromRecovery(value);
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthProvider.watchOf(context);
    final complete = auth.recoveryComplete;
    final ready = auth.recoveryReady;

    return Scaffold(
      backgroundColor: AppTheme.background,
      appBar: AppBar(title: const Text('Reset password')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Card(
            margin: const EdgeInsets.all(24),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: complete
                  ? _completion(auth)
                  : ready
                  ? _form(auth)
                  : _invalidLink(auth),
            ),
          ),
        ),
      ),
    );
  }

  Widget _completion(AuthProvider auth) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.check_circle_outline, size: 48, color: Colors.green),
      const SizedBox(height: 16),
      Text('Password updated', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      const Text(
        'Your password has been changed. Sign in with the new password.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: auth.finishRecovery,
        child: const Text('Return to sign in'),
      ),
    ],
  );

  Widget _invalidLink(AuthProvider auth) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      const Icon(Icons.link_off, size: 48),
      const SizedBox(height: 16),
      Text(
        'Reset link unavailable',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 10),
      Text(
        auth.recoveryError ?? 'This password-reset link is invalid or expired. Request a new link.',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: auth.finishRecovery,
        child: const Text('Return to sign in'),
      ),
    ],
  );

  Widget _form(AuthProvider auth) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'Choose a new password',
        style: Theme.of(context).textTheme.titleLarge,
      ),
      const SizedBox(height: 18),
      TextField(
        controller: _password,
        obscureText: true,
        autofillHints: const [AutofillHints.newPassword],
        decoration: const InputDecoration(
          labelText: 'New password',
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: 14),
      TextField(
        controller: _confirm,
        obscureText: true,
        decoration: const InputDecoration(
          labelText: 'Confirm new password',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (_) => auth.isLoading ? null : _update(),
      ),
      if (_formError != null || auth.recoveryError != null) ...[
        const SizedBox(height: 12),
        Text(
          _formError ?? auth.recoveryError!,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red),
        ),
      ],
      const SizedBox(height: 20),
      FilledButton(
        onPressed: auth.isLoading ? null : _update,
        child: auth.isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Text('Update password'),
      ),
    ],
  );
}
