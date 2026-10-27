# Mobile Supabase Auth callback configuration

This app uses `app_links` to receive the initial and subsequent native callback URIs. Recovery tokens are handed directly to Supabase Auth for validation; application code does not print callback URIs. A successful callback's refresh token is held in the platform secure store only as part of the active recovery session and is cleared after password update/sign-out.

## Operator values required before native release

Do not substitute example or guessed production values. Obtain and approve:

- the final Android application ID;
- the final iOS bundle ID;
- one exact Supabase Auth callback URI (scheme, host, and path), registered in Supabase Auth's redirect allow-list;
- confirmation that the password-reset email flow redirects to this URI.

The compile-time Dart value must be the complete exact URI:

```text
--dart-define=SUPABASE_AUTH_REDIRECT_URL=<operator-approved-full-callback-uri>
```

For local development, pass the public Supabase URL/key and redirect through the existing ignored `supabase.local.json` or Dart defines. Never put a service-role/secret key in this client.

## Native URI registration

### Android

`AndroidManifest.xml` receives placeholders from Gradle properties. With Flutter's CLI, supply the exact components of the approved URI, along with the approved application ID, using `--android-project-arg`:

```text
--android-project-arg=legalAndroidApplicationId=<approved-application-id>
--android-project-arg=authCallbackScheme=<approved-scheme>
--android-project-arg=authCallbackHost=<approved-host>
--android-project-arg=authCallbackPath=<approved-path>
```

The same properties can be passed to a direct Gradle invocation using `-Pname=value`.

Release Gradle tasks fail if the application ID or callback components are still the repository placeholders. The default manifest values are intentionally non-production and will not receive the approved callback.

### iOS

The Runner target uses the `LEGAL_IOS_BUNDLE_ID` and `LEGAL_AUTH_CALLBACK_SCHEME` Xcode build settings. Set these to the approved bundle ID and the exact scheme component before building/signing. The repository defaults are placeholders. No iOS build has been run in this environment because macOS/Xcode are unavailable.

Flutter's built-in deep-link handler is disabled so `app_links` is the single native callback owner. The app validates the callback scheme, host, path, token presence, expiry metadata (when provided), and the Supabase Auth user response before entering password recovery.

## Verification boundary

Unit tests exercise callback validation, missing/expired credentials, stream-injected relaunch delivery, password update, and session cleanup. They do not prove that an operator's installed Android/iOS build has the right application identity, OS URI registration, Supabase allow-list entry, email template, or signing configuration. Those must be supplied and verified on the actual device/store build before production use.
