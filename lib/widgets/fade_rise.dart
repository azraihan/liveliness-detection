import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Fades a block in while lifting it a few pixels. Screens stack these with
/// increasing [delay] so content arrives in reading order instead of all at
/// once — the whole entrance is one gesture, not an animation per element.
class FadeRise extends StatefulWidget {
  final Widget child;
  final Duration delay;
  final double offset;

  const FadeRise({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = 14,
  });

  @override
  State<FadeRise> createState() => _FadeRiseState();
}

class _FadeRiseState extends State<FadeRise>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Motion.slow,
  );
  late final Animation<double> _a =
      CurvedAnimation(parent: _c, curve: Motion.enter);

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _c.forward();
    } else {
      Future.delayed(widget.delay, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (reducedMotion(context)) return widget.child;

    return AnimatedBuilder(
      animation: _a,
      builder: (_, child) => Opacity(
        opacity: _a.value,
        child: Transform.translate(
          offset: Offset(0, (1 - _a.value) * widget.offset),
          child: child,
        ),
      ),
      child: widget.child,
    );
  }
}
