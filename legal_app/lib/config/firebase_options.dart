// ============================================================
//  Firebase configuration for the LEGAL SERVICES APP (mobile)
// ============================================================
//  HOW TO FILL THIS FILE:
//  1. Firebase Console > Project Settings > General > Your apps
//  2. Register an Android app (package: com.example.legalserviceapp)
//     and/or an iOS app (bundle id: com.example.legalserviceapp)
//  3. Copy the firebaseConfig values into the options below.
//
//  Alternatively use the FlutterFire CLI to generate this file:
//      dart pub global activate flutterfire_cli
//      flutterfire configure
//
//  The Admin Panel uses its OWN firebase_options.dart in
//  ../admin_panel/lib/config/firebase_options.dart
//  Both must point to the SAME Firebase project.
// ============================================================

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.windows:
      case TargetPlatform.macOS:
      case TargetPlatform.linux:
        // You can add desktop keys here if you run the app on desktop.
        return android;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  // ---------------------------------------------------------------
  //  TODO: Replace placeholders with YOUR Firebase project's values.
  // ---------------------------------------------------------------
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_WEB_API_KEY',
    appId: 'YOUR_WEB_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    authDomain: 'YOUR_PROJECT_ID.firebaseapp.com',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBlx1JNfFQ0o6pZmYo1bwf4ENAQ0Bu_6_U',
    appId: '1:248056839217:android:bd1dae6b8cddd71defe910',
    messagingSenderId: '248056839217',
    projectId: 'legal-102026',
    storageBucket: 'legal-102026.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',
    appId: 'YOUR_IOS_APP_ID',
    messagingSenderId: 'YOUR_MESSAGING_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    iosBundleId: 'com.example.legalserviceapp',
  );
}
