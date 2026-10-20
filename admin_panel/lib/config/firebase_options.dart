// ============================================================
//  Firebase configuration for the Legal Services Admin Panel
// ============================================================
//  HOW TO FILL THIS FILE:
//  1. Go to Firebase Console > Project Settings > General
//  2. Under "Your apps", add a WEB app (or use an existing one)
//  3. Copy the firebaseConfig values and paste them below.
//  4. Save and run:  flutter run -d chrome
//
//  Alternatively run the FlutterFire CLI once your project exists:
//      dart pub global activate flutterfire_cli
//      flutterfire configure
//  It will regenerate this file automatically.
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
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }

  // ---------------------------------------------------------------
  //  TODO: Replace the placeholder values below with YOUR project's
  //  values from the Firebase Console (Project Settings > General).
  // ---------------------------------------------------------------

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyD73nJA-v9JhmVLE_MUhr-LNCZ9WYdDPwo',
    appId: '1:248056839217:web:ee1094553c01a51eefe910',
    messagingSenderId: '248056839217',
    projectId: 'legal-102026',
    authDomain: 'legal-102026.firebaseapp.com',
    storageBucket: 'legal-102026.firebasestorage.app',
    measurementId: 'G-0S9CQPJRE5',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyBlx1JNfFQ0o6pZmYo1bwf4ENAQ0Bu_6_U',
    appId: '1:248056839217:android:1bb803c519e5648cefe910',
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
    iosBundleId: 'com.example.legalAdmin',
  );
}
