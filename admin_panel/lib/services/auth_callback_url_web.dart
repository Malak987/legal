import 'package:web/web.dart' as web;

/// Remove auth callback material from browser history immediately after
/// parsing. No callback value is logged or written to persistent storage.
void clearAuthCallbackFromAddressBar() {
  final path = web.window.location.pathname;
  web.window.history.replaceState(
    null,
    web.document.title,
    path.isEmpty ? '/' : path,
  );
}
