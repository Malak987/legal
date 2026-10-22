/// Configuration for the Google Generative Language (Gemini) features.
///
/// **The API key is deliberately not in this repository.** A literal key used
/// to live in three screens; because it was committed and shipped inside the
/// app it has to be treated as compromised and revoked (see README section 6).
///
/// Supply the replacement at build time:
///
///     flutter run   --dart-define=GEMINI_API_KEY=...
///     flutter build apk --dart-define=GEMINI_API_KEY=...
///
/// With no key the AI screens still open, and report that the feature is not
/// configured instead of calling Google with an empty key.
///
/// A key compiled into a client app can always be extracted from the binary:
/// `--dart-define` keeps it out of version control, but it does not make it
/// secret. For production these calls belong behind the backend, so the key
/// never leaves the server.
class AiConfig {
  const AiConfig._();

  /// Empty unless `--dart-define=GEMINI_API_KEY=...` was passed at build time.
  static const String apiKey = String.fromEnvironment('GEMINI_API_KEY');

  /// The model every AI screen in this app talks to.
  static const String model = 'gemini-1.5-flash';

  static bool get isConfigured => apiKey.trim().isNotEmpty;

  /// Shown by the AI screens when no key was supplied at build time.
  static const String notConfiguredMessage =
      'AI features are not configured for this build. '
      'Rebuild with --dart-define=GEMINI_API_KEY=<key>.';

  /// The (key-free) endpoint. The key travels in a header, not the query
  /// string, so it cannot leak through URLs, proxy logs or crash reports.
  static Uri generateContentUri() => Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        '$model:generateContent',
      );

  /// Request headers for a configured build.
  static Map<String, String> get headers => {
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      };
}
