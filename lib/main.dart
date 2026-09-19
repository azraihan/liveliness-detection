import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'pages/landing_page.dart';
import 'services/liveness_model.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);

  // Start loading the model now, in the background, so it is ready by the time
  // the user has read the landing screen. Deliberately not awaited — the UI
  // must not wait on it.
  unawaited(LivenessModel.instance.load());

  runApp(const FaceLivenessApp());
}

class FaceLivenessApp extends StatefulWidget {
  const FaceLivenessApp({super.key});

  @override
  State<FaceLivenessApp> createState() => _FaceLivenessAppState();
}

class _FaceLivenessAppState extends State<FaceLivenessApp> {
  final ThemeController _theme = ThemeController();

  @override
  void dispose() {
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ThemeScope(
      controller: _theme,
      child: ValueListenableBuilder<ThemeMode>(
        valueListenable: _theme,
        builder: (context, mode, _) {
          return MaterialApp(
            title: 'Face Liveness',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: mode,
            home: const LandingPage(),
            builder: (context, child) {
              // Match the status/nav bar to the page so the chrome disappears
              // into the background in whichever mode is active.
              final isDark = Theme.of(context).brightness == Brightness.dark;
              final p = context.palette;
              return AnnotatedRegion<SystemUiOverlayStyle>(
                value: SystemUiOverlayStyle(
                  statusBarColor: Colors.transparent,
                  statusBarIconBrightness:
                      isDark ? Brightness.light : Brightness.dark,
                  statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
                  systemNavigationBarColor: p.background,
                  systemNavigationBarIconBrightness:
                      isDark ? Brightness.light : Brightness.dark,
                ),
                child: child!,
              );
            },
          );
        },
      ),
    );
  }
}
