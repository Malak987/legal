# admin_panel — administrator console

Flutter app (web/desktop) for users, lawyers, cases, bookings, plans,
subscriptions, reviews, chats and notifications. Requires an account whose
`users/{uid}` document has `role: "admin"`; the API enforces that independently,
so a non-admin build cannot do anything an administrator could not.

```bash
flutter pub get
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:5000/api
flutter analyze
flutter test
```

The console reads only its own profile document through the Firestore SDK (to
decide whether to show any UI at all); every other read and write goes through
the REST API. The Firestore rules that permit exactly that are in
[`firestore.rules`](../firestore.rules) — deploy them with
`firebase deploy --only firestore:rules` from the repository root.

See the repository [README](../README.md) for the API reference and setup.
