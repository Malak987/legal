/// Safely extracts a Supabase password-recovery callback without exposing
/// bearer tokens through diagnostics or string representations.
class RecoveryCallback {
  const RecoveryCallback._({
    required this.isAuthCallback,
    required this.type,
    required this.accessToken,
    required this.errorCode,
    required this.expiresIn,
    required this.expiresAt,
  });

  const RecoveryCallback.none()
    : this._(
        isAuthCallback: false,
        type: null,
        accessToken: null,
        errorCode: null,
        expiresIn: null,
        expiresAt: null,
      );

  final bool isAuthCallback;
  final String? type;
  final String? accessToken;
  final String? errorCode;
  final int? expiresIn;
  final int? expiresAt;

  bool get isRecovery => isAuthCallback && type?.toLowerCase() == 'recovery';
  bool get hasError => errorCode != null && errorCode!.isNotEmpty;

  /// Callback values normally arrive in the fragment. Query parameters are
  /// also accepted for server-side error redirects and compatible templates.
  /// Unknown fragments (for example a Flutter route) are ignored.
  factory RecoveryCallback.parse(Uri? uri) {
    if (uri == null) return const RecoveryCallback.none();

    final values = <String, String>{...uri.queryParameters};
    final fragment = uri.fragment;
    if (fragment.isNotEmpty && !fragment.startsWith('/')) {
      try {
        values.addAll(Uri.splitQueryString(fragment));
      } on FormatException {
        // A non-auth fragment is not a password-reset callback.
      }
    }

    const callbackKeys = <String>{
      'access_token',
      'refresh_token',
      'type',
      'error',
      'error_code',
      'error_description',
    };
    final isCallback = values.keys.any(callbackKeys.contains);
    if (!isCallback) return const RecoveryCallback.none();

    final type = values['type']?.trim().toLowerCase();
    final errorCode = (values['error_code'] ?? values['error'] ?? '').trim();
    return RecoveryCallback._(
      isAuthCallback: true,
      type: type,
      accessToken: values['access_token']?.trim(),
      errorCode: errorCode,
      expiresIn: int.tryParse(values['expires_in'] ?? ''),
      expiresAt: int.tryParse(values['expires_at'] ?? ''),
    );
  }

  /// Never include callback values in diagnostics.
  @override
  String toString() =>
      'RecoveryCallback(isAuthCallback: $isAuthCallback, '
      'type: $type, hasAccessToken: ${accessToken?.isNotEmpty == true}, '
      'hasError: $hasError)';
}
