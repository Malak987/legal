import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'config/firebase_options.dart';
import 'views/splash/splashscreen.dart';
import 'constants/colors.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase so the API layer can authenticate requests.
  // If your firebase_options.dart still has placeholder values this will
  // throw; the app catches it so the UI still loads (using static data).
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  } catch (e) {
    debugPrint('Firebase initialization failed: $e');
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Legal Services App',
      theme: ThemeData(
        scaffoldBackgroundColor: AppColors.bgColor,
        useMaterial3: true,
      ),
      home: SplashScreen(),
    );
  }
}