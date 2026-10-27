/// No-op on non-web platforms. The browser implementation removes callback
/// query/fragment values from the address bar once recovery credentials are
/// captured in memory.
void clearAuthCallbackFromAddressBar() {}
