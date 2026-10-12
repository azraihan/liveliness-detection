import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Whether the ML Kit challenge stage runs at all.
///
/// On, the pipeline is three stages and the challenges gate the other two.
/// Off, it is the two-stage passive check: MobileNetV2, then the ensemble.
/// Exposed as a [ValueNotifier] so the landing page switch and the
/// verification screen read the same value without a state-management layer.
class ChallengeSettings extends ValueNotifier<bool> {
  ChallengeSettings._() : super(defaultEnabled);

  static final ChallengeSettings instance = ChallengeSettings._();

  /// On by default: the demo should show the full pipeline unless someone
  /// deliberately turns the gate off.
  static const bool defaultEnabled = true;

  static const String _key = 'challenge_stage_enabled';

  bool get enabled => value;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = prefs.getBool(_key) ?? defaultEnabled;
    } catch (e) {
      debugPrint('ChallengeSettings load error: $e');
    }
  }

  Future<void> setEnabled(bool next) async {
    if (value == next) return;
    value = next;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_key, next);
    } catch (e) {
      debugPrint('ChallengeSettings save error: $e');
    }
  }
}
