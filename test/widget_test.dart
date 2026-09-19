import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:face_liveness_demo/main.dart';
import 'package:face_liveness_demo/theme/app_theme.dart';

/// The landing screen runs a looping orbit animation, so `pumpAndSettle` would
/// never return. Pumping a fixed span past the entry stagger is enough.
Future<void> _settleEntry(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

void main() {
  // The default 800×600 test surface is nothing like a phone; pin a portrait
  // handset so layout assertions mean something.
  setUp(() {
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1170, 2532); // iPhone 13 class
    view.devicePixelRatio = 3.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });
  });

  testWidgets('landing screen renders its copy and checklist', (tester) async {
    await tester.pumpWidget(const FaceLivenessApp());
    await _settleEntry(tester);

    expect(find.text('Verify your\nidentity'), findsOneWidget);
    expect(find.text('Begin verification'), findsOneWidget);
    expect(find.text('Even lighting'), findsOneWidget);
    expect(find.text('Eyes visible'), findsOneWidget);
    expect(find.text('Hold steady'), findsOneWidget);
  });

  testWidgets('theme toggle flips light to dark and back', (tester) async {
    await tester.pumpWidget(const FaceLivenessApp());
    await _settleEntry(tester);

    Brightness brightnessOf() =>
        Theme.of(tester.element(find.byType(Scaffold))).brightness;

    // Test bindings report a light platform brightness, and ThemeMode.system
    // follows it.
    expect(brightnessOf(), Brightness.light);

    // One frame applies the new ThemeMode and starts MaterialApp's
    // AnimatedTheme; the next one carries that cross-fade to completion.
    Future<void> tapAndSettleTheme(IconData icon) async {
      await tester.tap(find.byIcon(icon));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
    }

    await tapAndSettleTheme(Icons.dark_mode_outlined);
    expect(brightnessOf(), Brightness.dark);

    await tapAndSettleTheme(Icons.light_mode_outlined);
    expect(brightnessOf(), Brightness.light);
  });

  testWidgets('palette tokens resolve in both themes', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Builder(
          builder: (context) => Text('${context.palette.ink}'),
        ),
      ),
    );

    expect(find.text('${AppPalette.dark.ink}'), findsOneWidget);
  });
}
