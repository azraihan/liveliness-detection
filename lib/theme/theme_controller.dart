import 'package:flutter/material.dart';

/// Holds the app's [ThemeMode]. Starts at [ThemeMode.system] so the app opens
/// in whatever the phone is already set to; the first toggle pins it to the
/// opposite of what is currently on screen.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system);

  /// Flips to the opposite of what the user is looking at right now, which is
  /// why the caller passes the *resolved* brightness rather than the mode.
  void toggle(Brightness current) {
    value = current == Brightness.dark ? ThemeMode.light : ThemeMode.dark;
  }

  void followSystem() => value = ThemeMode.system;
}

/// Makes the controller reachable from any screen without a state package.
class ThemeScope extends InheritedNotifier<ThemeController> {
  const ThemeScope({
    super.key,
    required ThemeController controller,
    required super.child,
  }) : super(notifier: controller);

  static ThemeController of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<ThemeScope>();
    assert(scope != null, 'ThemeScope is missing above this widget');
    return scope!.notifier!;
  }
}
