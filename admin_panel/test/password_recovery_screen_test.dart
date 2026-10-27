import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:legal_admin/providers/auth_provider.dart';
import 'package:legal_admin/screens/password_recovery_screen.dart';
import 'package:legal_admin/services/auth_service.dart';
import 'package:provider/provider.dart';

import 'fakes.dart';

Widget _app(AuthProvider provider) =>
    ChangeNotifierProvider<AuthProvider>.value(
      value: provider,
      child: const MaterialApp(home: PasswordRecoveryScreen()),
    );

void main() {
  testWidgets('valid callback updates the password and confirms sign-in', (
    tester,
  ) async {
    final service = FakeAuthService(api: FakeApiService())
      ..recoveryResult = const RecoveryCallbackResult.ready();
    final provider = AuthProvider(service);
    await provider.restore(callbackUri: Uri.parse('test://unit/callback'));
    await tester.pumpWidget(_app(provider));

    await tester.enterText(find.byType(TextField).at(0), 'a-new-password-123');
    await tester.enterText(find.byType(TextField).at(1), 'a-new-password-123');
    await tester.tap(find.text('Update password'));
    await tester.pumpAndSettle();

    expect(service.recoveryUpdateCalls, 1);
    expect(find.text('Password updated'), findsOneWidget);
    await tester.tap(find.text('Return to sign in'));
    await tester.pumpAndSettle();
    expect(provider.status, AuthStatus.unauthenticated);
  });

  testWidgets(
    'invalid callback displays an expired-link message without password fields',
    (tester) async {
      final service = FakeAuthService(api: FakeApiService())
        ..recoveryResult = const RecoveryCallbackResult(
          RecoveryCallbackStatus.invalid,
          message: 'This password-reset link is invalid or expired. Request a new link.',
        );
      final provider = AuthProvider(service);
      await provider.restore(callbackUri: Uri.parse('test://unit/callback'));
      await tester.pumpWidget(_app(provider));

      expect(find.text('Reset link unavailable'), findsOneWidget);
      expect(find.textContaining('invalid or expired'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    },
  );
}
