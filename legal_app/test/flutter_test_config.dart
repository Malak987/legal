import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Keep widget tests deterministic and offline by routing Google Fonts HTTP requests
/// through a controlled MockClient.
Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = true;
  GoogleFonts.config.httpClient = MockClient((request) async {
    return http.Response('dummy-font-bytes', 200);
  });
  await testMain();
}
