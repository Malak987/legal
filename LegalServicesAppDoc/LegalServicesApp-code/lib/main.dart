import 'package:legalserviceapp/views/splash/splashscreen.dart';
import 'package:flutter/material.dart';

import 'Constants/colors.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  // This widget is the root of your application.
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
