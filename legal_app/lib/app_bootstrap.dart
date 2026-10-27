import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'config/supabase_client_config.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'state/session_controller.dart';
import 'views/configuration/supabase_config_error_screen.dart';

/// Startup sequence: validate the compiled Supabase configuration first, then
/// build exactly one Supabase session (Auth gateway + data client sharing the
/// same validated config) and start restoring the persisted session.
///
/// With an invalid configuration no Supabase client is created and no network
/// request is made; a configuration screen explains how to rebuild.
Widget bootstrapApp({
  required Widget Function(SessionController session) buildApp,
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
  return buildApp(session);
}

/// Wires one [SupabaseAuthGateway] and one [ApiClient] to the same validated
/// [config]. [httpClient] and [sessionStore] are injection points for tests.
SessionController createSupabaseSession(
  SupabaseClientConfig config, {
  http.Client? httpClient,
  AuthSessionStore? sessionStore,
  Stream<Uri>? recoveryLinkStream,
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
  return SessionController(
    auth: AuthService(gateway: gateway, api: api),
    recoveryLinkStream: recoveryLinkStream,
  );
}
