import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

/// A 40px icon button that flips light ↔ dark. The glyph cross-fades and
/// rotates a quarter turn so the change reads as one movement.
class ThemeToggle extends StatelessWidget {
  const ThemeToggle({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Semantics(
      button: true,
      label: isDark ? 'Switch to light mode' : 'Switch to dark mode',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => ThemeScope.of(context)
            .toggle(Theme.of(context).brightness),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                border: Border.all(color: p.border),
                borderRadius: BorderRadius.circular(Radii.sm),
              ),
              child: AnimatedSwitcher(
                duration: Motion.base,
                switchInCurve: Motion.enter,
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: RotationTransition(
                    turns: Tween<double>(begin: 0.75, end: 1.0).animate(anim),
                    child: child,
                  ),
                ),
                child: Icon(
                  isDark
                      ? Icons.light_mode_outlined
                      : Icons.dark_mode_outlined,
                  key: ValueKey(isDark),
                  size: 17,
                  color: p.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
