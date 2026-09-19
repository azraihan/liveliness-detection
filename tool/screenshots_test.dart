// Screenshot harness — NOT part of the test suite.
//
//   flutter test tool/screenshots_test.dart --update-goldens
//
// Writes a PNG of every screen in both themes to docs/screens/. It lives
// outside test/ on purpose: `flutter test` would otherwise compare these as
// goldens, and they render slightly differently on every machine.
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:face_liveness_demo/pages/landing_page.dart';
import 'package:face_liveness_demo/pages/liveness_page.dart';
import 'package:face_liveness_demo/pages/success_page.dart';
import 'package:face_liveness_demo/painters/scan_ring_painter.dart';
import 'package:face_liveness_demo/theme/app_theme.dart';
import 'package:face_liveness_demo/theme/theme_controller.dart';

Future<void> _loadFonts() async {
  final inter = FontLoader('Inter');
  for (final w in ['Light', 'Regular', 'Medium', 'SemiBold']) {
    final bytes = File('assets/fonts/Inter-$w.ttf').readAsBytesSync();
    inter.addFont(Future.value(bytes.buffer.asByteData()));
  }
  await inter.load();

  // Pulled out of the built bundle so icons render as glyphs, not tofu.
  final iconFile = File('build/flutter_assets/fonts/MaterialIcons-Regular.otf');
  if (iconFile.existsSync()) {
    final icons = FontLoader('MaterialIcons')
      ..addFont(
          Future.value(iconFile.readAsBytesSync().buffer.asByteData()));
    await icons.load();
  }
}

void main() {
  setUpAll(_loadFonts);

  setUp(() {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1170, 2532);
    view.devicePixelRatio = 3.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  Future<void> shoot(
    WidgetTester tester,
    String name,
    Widget home,
    ThemeMode mode,
  ) async {
    await tester.pumpWidget(
      ThemeScope(
        controller: ThemeController(),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          home: home,
        ),
      ),
    );
    // The entry stagger needs real frames to advance, not one long jump.
    for (var i = 0; i < 48; i++) {
      await tester.pump(const Duration(milliseconds: 40));
    }
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('../docs/screens/$name.png'),
    );
  }

  testWidgets('landing light', (t) =>
      shoot(t, 'landing-light', const LandingPage(), ThemeMode.light));
  testWidgets('landing dark', (t) =>
      shoot(t, 'landing-dark', const LandingPage(), ThemeMode.dark));

  testWidgets('success light', (t) => shoot(
      t, 'success-light', const SuccessPage(confidence: 0.973), ThemeMode.light));
  testWidgets('success dark', (t) => shoot(
      t, 'success-dark', const SuccessPage(confidence: 0.973), ThemeMode.dark));

  // No camera or model in the test host, so this captures the PREPARING state.
  testWidgets('liveness light', (t) =>
      shoot(t, 'liveness-light', const LivenessPage(), ThemeMode.light));
  testWidgets('liveness dark', (t) =>
      shoot(t, 'liveness-dark', const LivenessPage(), ThemeMode.dark));

  // The capturing state needs a camera, so the viewfinder's painters are
  // reproduced here at a fixed phase to check the tick band on its own.
  testWidgets('capture ticks', (t) => shoot(
      t, 'viewfinder-ticks', const _TicksPreview(), ThemeMode.light));
  testWidgets('capture ticks dark', (t) => shoot(
      t, 'viewfinder-ticks-dark', const _TicksPreview(), ThemeMode.dark));
}

class _TicksPreview extends StatelessWidget {
  const _TicksPreview();

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    const boxD = 320.0;
    const tickBand = 18.0;
    const cameraD = boxD - tickBand * 2 - 28;

    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          // Four phases of the wave, so the travelling crests are visible in
          // a still image.
          children: [0.0, 0.25].map((phase) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: SizedBox(
                width: boxD,
                height: boxD,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: const Size(boxD, boxD),
                      painter: CaptureTicksPainter(
                        phase: AlwaysStoppedAnimation(phase),
                        amplitude: const AlwaysStoppedAnimation(1.0),
                        color: p.ink,
                        inset: tickBand,
                        still: false,
                      ),
                    ),
                    CustomPaint(
                      size: const Size(boxD, boxD),
                      painter: ScanRingPainter(
                        progress: 0.45,
                        spin: 0,
                        indeterminate: false,
                        trackColor: p.border,
                        arcColor: p.ink,
                        inset: tickBand,
                      ),
                    ),
                    Container(
                      width: cameraD,
                      height: cameraD,
                      decoration: BoxDecoration(
                        color: p.surfaceMuted,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
