import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:face_liveness_demo/main.dart';
import 'package:face_liveness_demo/services/challenge_settings.dart';

/// The landing screen loops an orbit animation, so `pumpAndSettle` would never
/// return. Pumping past the entry stagger is enough.
Future<void> _settleEntry(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 1200));
}

void main() {
  setUp(() async {
    final view =
        TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.physicalSize = const Size(1170, 2532);
    view.devicePixelRatio = 3.0;
    addTearDown(() {
      view.resetPhysicalSize();
      view.resetDevicePixelRatio();
    });

    SharedPreferences.setMockInitialValues({});
    await ChallengeSettings.instance.setEnabled(true);
  });

  testWidgets('tapping the switch turns the challenge layer off, then on',
      (tester) async {
    await tester.pumpWidget(const FaceLivenessApp());
    await _settleEntry(tester);

    expect(ChallengeSettings.instance.enabled, isTrue);

    final toggle = find.byType(Switch);
    await tester.ensureVisible(toggle);

    // The switch sits inside a tappable row. If both handled the tap it would
    // flip twice and appear to do nothing, which is the bug to rule out.
    await tester.tap(toggle);
    await tester.pump();
    expect(ChallengeSettings.instance.enabled, isFalse);
    expect(tester.widget<Switch>(toggle).value, isFalse);
    expect(find.textContaining('Skipped'), findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();
    expect(ChallengeSettings.instance.enabled, isTrue);
    expect(tester.widget<Switch>(toggle).value, isTrue);
  });

  testWidgets('tapping the row label also flips it, exactly once',
      (tester) async {
    await tester.pumpWidget(const FaceLivenessApp());
    await _settleEntry(tester);

    final label = find.text('Challenge check');
    await tester.ensureVisible(label);
    await tester.tap(label);
    await tester.pump();

    expect(ChallengeSettings.instance.enabled, isFalse);
  });

  test('the choice survives an app restart', () async {
    await ChallengeSettings.instance.setEnabled(false);
    // Simulate a fresh launch reading it back from storage.
    ChallengeSettings.instance.value = true;
    await ChallengeSettings.instance.load();
    expect(ChallengeSettings.instance.enabled, isFalse);
  });
}
