import 'dart:convert';

import 'app_config.dart';

/// A specific reason why the compiled Supabase configuration is unusable.
enum SupabaseConfigIssue {
  missingUrl,
  malformedUrl,
  insecureUrl,
  missingKey,
  malformedKey,
  secretKey,
  projectMismatch,
}

/// The single, validated source of Supabase client configuration.
///
/// Values come from compile-time Dart defines (see [AppConfig]); they are
/// validated once at startup by `main()` and the same instance is shared by
/// authentication, session restoration and every PostgREST/RPC request.
///
/// The public key is never included in [errorMessage], [issueDescriptions] or
/// [toString]; use [redactedKey] when a diagnostic needs to mention it.
class SupabaseConfig {
  SupabaseConfig._({
    required this.url,
    required this.anonKey,
    required List<SupabaseConfigIssue> issues,
  }) : issues = List.unmodifiable(issues);

  /// Validates raw values.
  ///
  /// [requireKnownKeyFormat] rejects keys that are neither a Supabase
  /// publishable key (`sb_publishable_…`) nor a legacy anon JWT, which catches
  /// copied placeholders and CI dummy values before any network request. It is
  /// relaxed only for explicitly injected test doubles. Secret and
  /// service-role keys are rejected in every mode.
  factory SupabaseConfig.resolve({
    required String url,
    required String anonKey,
    bool requireKnownKeyFormat = true,
  }) {
    final normalizedUrl = _normalizeUrl(url);
    final key = anonKey.trim();
    final issues = <SupabaseConfigIssue>[];

    if (normalizedUrl.isEmpty) {
      issues.add(SupabaseConfigIssue.missingUrl);
    } else {
      final urlIssue = _validateUrl(normalizedUrl);
      if (urlIssue != null) issues.add(urlIssue);
    }

    final jwtClaims = _jwtClaims(key);
    if (key.isEmpty) {
      issues.add(SupabaseConfigIssue.missingKey);
    } else if (key.startsWith('sb_secret_') ||
        jwtClaims?['role'] == 'service_role') {
      issues.add(SupabaseConfigIssue.secretKey);
    } else if (requireKnownKeyFormat && !_isKnownPublicKey(key, jwtClaims)) {
      issues.add(SupabaseConfigIssue.malformedKey);
    }

    final ref = jwtClaims?['ref'];
    final host = Uri.tryParse(normalizedUrl)?.host ?? '';
    if (ref is String &&
        ref.isNotEmpty &&
        host.endsWith('.supabase.co') &&
        host.split('.').first != ref) {
      issues.add(SupabaseConfigIssue.projectMismatch);
    }

    return SupabaseConfig._(url: normalizedUrl, anonKey: key, issues: issues);
  }

  /// Chooses the configuration for a service.
  ///
  /// An explicit [config] wins. Explicit [url]/[anonKey] overrides (used by
  /// tests with fake HTTP clients) are validated without the key-format check.
  /// Otherwise the startup [environment] configuration is shared.
  factory SupabaseConfig.select({
    SupabaseConfig? config,
    String? url,
    String? anonKey,
  }) {
    if (config != null) return config;
    if (url == null && anonKey == null) return environment;
    return SupabaseConfig.resolve(
      url: url ?? AppConfig.supabaseUrl,
      anonKey: anonKey ?? AppConfig.supabaseAnonKey,
      requireKnownKeyFormat: false,
    );
  }

  /// Compile-time configuration, validated exactly once per app process.
  static final SupabaseConfig environment = SupabaseConfig.resolve(
    url: AppConfig.supabaseUrl,
    anonKey: AppConfig.supabaseAnonKey,
  );

  /// Dart define names. Keep in sync with `scripts/supabase_env.mjs`.
  static const String urlDefine = AppConfig.supabaseUrlDefine;
  static const String keyDefine = AppConfig.supabaseAnonKeyDefine;

  /// Placeholder previously injected by CI. It is never a usable key.
  static const String legacyCiPlaceholderKey =
      'ci-public-anon-key-for-build-only';

  /// Project base URL without a trailing slash.
  final String url;

  /// Public anon/publishable key. Never log or display this value.
  final String anonKey;

  final List<SupabaseConfigIssue> issues;

  bool get isValid => issues.isEmpty;

  /// A non-secret description such as `sb_publishable_… (46 chars)`.
  String get redactedKey {
    if (anonKey.isEmpty) return '(missing)';
    if (anonKey.startsWith('sb_publishable_')) {
      return 'sb_publishable_… (${anonKey.length} chars)';
    }
    if (anonKey.startsWith('sb_secret_')) {
      return 'sb_secret_… (${anonKey.length} chars)';
    }
    if (_jwtClaims(anonKey) != null) {
      return 'JWT … (${anonKey.length} chars)';
    }
    return '… (${anonKey.length} chars)';
  }

  /// One sentence per issue. Never contains the key value.
  List<String> get issueDescriptions =>
      issues.map(describeIssue).toList(growable: false);

  static String describeIssue(SupabaseConfigIssue issue) {
    switch (issue) {
      case SupabaseConfigIssue.missingUrl:
        return '$urlDefine is empty.';
      case SupabaseConfigIssue.malformedUrl:
        return '$urlDefine must be the project base URL, for example '
            'https://<project-ref>.supabase.co, with no path such as '
            '/rest/v1 or /auth/v1, query string or credentials.';
      case SupabaseConfigIssue.insecureUrl:
        return '$urlDefine must use https (http is only allowed for '
            'localhost).';
      case SupabaseConfigIssue.missingKey:
        return '$keyDefine is empty: the public anon/publishable key was not '
            'compiled into this build.';
      case SupabaseConfigIssue.malformedKey:
        return '$keyDefine is not a Supabase public key. Use the project '
            'publishable key (sb_publishable_…) or legacy anon key, not a '
            'placeholder.';
      case SupabaseConfigIssue.secretKey:
        return '$keyDefine contains a secret/service-role key. Only the public '
            'anon/publishable key may be used in the admin panel.';
      case SupabaseConfigIssue.projectMismatch:
        return '$keyDefine belongs to a different Supabase project than '
            '$urlDefine.';
    }
  }

  /// Developer-facing commands. Placeholders only; never real values.
  static const String runCommandHint =
      'flutter run -d chrome --dart-define=$urlDefine=https://<project-ref>.supabase.co '
      '--dart-define=$keyDefine=<public anon/publishable key>';

  /// Actionable error for logs and the UI. Never contains the key value.
  String get errorMessage {
    if (isValid) return '';
    return 'Supabase authentication is not configured. '
        '${issueDescriptions.join(' ')} '
        'Provide the values at compile time with --dart-define '
        '(for example: node scripts/run_web.mjs, or $runCommandHint), then '
        'fully restart the app. Hot restart, shell environment variables and '
        'hosting environment variables do not change compiled Dart defines.';
  }

  @override
  String toString() =>
      'SupabaseConfig(url: $url, key: $redactedKey, issues: ${issues.map((i) => i.name).join(', ')})';

  static String _normalizeUrl(String raw) {
    var value = raw.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  static SupabaseConfigIssue? _validateUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        (uri.scheme != 'https' && uri.scheme != 'http') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        value.contains(RegExp(r'\s'))) {
      return SupabaseConfigIssue.malformedUrl;
    }
    if (uri.scheme == 'http' && !_loopbackHosts.contains(uri.host)) {
      return SupabaseConfigIssue.insecureUrl;
    }
    return null;
  }

  static const Set<String> _loopbackHosts = {'localhost', '127.0.0.1', '::1'};

  static bool _isKnownPublicKey(String key, Map<String, Object?>? claims) {
    if (key == legacyCiPlaceholderKey) return false;
    if (key.startsWith('sb_publishable_')) {
      return RegExp(r'^sb_publishable_[A-Za-z0-9_-]{10,}$').hasMatch(key);
    }
    return claims != null && claims['role'] == 'anon';
  }

  static Map<String, Object?>? _jwtClaims(String key) {
    final parts = key.split('.');
    if (parts.length != 3 || parts.any((part) => part.isEmpty)) return null;
    try {
      final payload = utf8.decode(
        base64Url.decode(base64Url.normalize(parts[1])),
      );
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }
}
