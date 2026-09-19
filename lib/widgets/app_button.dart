import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

enum AppButtonVariant {
  /// Solid ink fill — one per screen, the single strongest mark on the page.
  solid,

  /// Hairline outline, no fill. For anything secondary.
  quiet,
}

/// The app's only button. Presses settle inward a touch rather than rippling,
/// which keeps the surface calm.
class AppButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? trailingIcon;

  const AppButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = AppButtonVariant.solid,
    this.trailingIcon,
  });

  @override
  State<AppButton> createState() => _AppButtonState();
}

class _AppButtonState extends State<AppButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final enabled = widget.onPressed != null;
    final solid = widget.variant == AppButtonVariant.solid;

    final fg = solid ? p.onInk : p.textPrimary;

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
        onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
        onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
        onTap: widget.onPressed,
        child: AnimatedScale(
          scale: _pressed ? 0.985 : 1.0,
          duration: Motion.fast,
          curve: Motion.standard,
          child: AnimatedOpacity(
            opacity: enabled ? 1.0 : 0.35,
            duration: Motion.fast,
            child: AnimatedContainer(
              duration: Motion.fast,
              height: 56, // comfortably past the 44px touch minimum
              width: double.infinity,
              decoration: BoxDecoration(
                color: solid
                    ? (_pressed ? p.ink.withValues(alpha: 0.88) : p.ink)
                    : (_pressed ? p.surfaceMuted : Colors.transparent),
                borderRadius: BorderRadius.circular(Radii.md),
                border: solid ? null : Border.all(color: p.border),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    widget.label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: fg,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  if (widget.trailingIcon != null) ...[
                    const SizedBox(width: Space.sm),
                    Icon(widget.trailingIcon, size: 16, color: fg),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
