import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/landing_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  runApp(const FaceLivenessApp());
}

class FaceLivenessApp extends StatelessWidget {
  const FaceLivenessApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Face Liveness',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF080C14),
      ),
      home: const LandingPage(),
    );
  }
}
