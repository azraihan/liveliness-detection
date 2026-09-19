import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Reveals a short label one character at a time.
///
/// With [repeat] the reveal runs as a loop: glyphs rise in left to right, the
/// word holds long enough to be read, then the glyphs continue upward and out
/// before the cycle starts again. The motion always travels the same way, so
/// it reads as a slow flow rather than a blink.
///
/// One controller drives every glyph; each one just samples the shared clock
/// at its own offset. The [Text] widgets are built once per frame-independent
/// rebuild and reused across frames, so the glyphs never re-layout.
class StaggeredLabel extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final Duration delay;

  /// Loop the reveal instead of playing it once.
  final bool repeat;

  const StaggeredLabel({
    super.key,
    required this.text,
    this.style,
    this.delay = Duration.zero,
    this.repeat = false,
  });

  @override
  State<StaggeredLabel> createState() => _StaggeredLabelState();
}

class _StaggeredLabelState extends State<StaggeredLabel>
    with SingleTickerProviderStateMixin {
  // Cycle: glyphs in ─ hold ─ glyphs out ─ gap ─ repeat.
  //
  // The hold dominates on purpose. A wordmark that is missing for any real
  // length of time reads as a glitch, so the word sits fully legible for about
  // 70% of the ~5s cycle and the blank gap is barely a beat.
  static const double _staggerMs = 45;
  static const double _charInMs = 300;
  static const double _holdMs = 3600;
  static const double _charOutMs = 240;
  static const double _gapMs = 350;

  /// Vertical travel per glyph. Small on purpose — this is an 10px label.
  static const double _rise = 6;

  late final List<String> _chars = widget.text.split('');
  late final double _lastStagger = _staggerMs * (_chars.length - 1);

  late final double _revealEndMs = _lastStagger + _charInMs;
  late final double _outStartMs = _revealEndMs + _holdMs;
  late final double _totalMs = widget.repeat
      ? _outStartMs + _lastStagger + _charOutMs + _gapMs
      : _revealEndMs;

  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: Duration(milliseconds: _totalMs.round()),
  );

  @override
  void initState() {
    super.initState();
    void start() {
      if (!mounted) return;
      widget.repeat ? _c.repeat() : _c.forward();
    }

    if (widget.delay == Duration.zero) {
      start();
    } else {
      Future.delayed(widget.delay, start);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Opacity and vertical offset for glyph [i] at [ms] into the cycle.
  (double, double) _glyphAt(int i, double ms) {
    final inStart = _staggerMs * i;
    final inEnd = inStart + _charInMs;

    if (ms < inStart) return (0, _rise);
    if (ms < inEnd) {
      final t = Curves.easeOutCubic
          .transform(((ms - inStart) / _charInMs).clamp(0.0, 1.0));
      return (t, (1 - t) * _rise);
    }

    if (!widget.repeat) return (1, 0);

    final outStart = _outStartMs + _staggerMs * i;
    if (ms < outStart) return (1, 0);

    final outEnd = outStart + _charOutMs;
    if (ms < outEnd) {
      // Exits upward, continuing the direction it entered from.
      final t = Curves.easeInCubic
          .transform(((ms - outStart) / _charOutMs).clamp(0.0, 1.0));
      return (1 - t, -t * _rise);
    }
    return (0, -_rise);
  }

  @override
  Widget build(BuildContext context) {
    // Reduced motion gets the label, just not the performance.
    if (reducedMotion(context)) {
      return Text(widget.text, style: widget.style);
    }

    // Built here, outside the per-frame builder, so each frame reuses the same
    // Text instances and only the Opacity/Transform above them change.
    final glyphs = [
      for (final ch in _chars) Text(ch, style: widget.style),
    ];

    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final ms = _c.value * _totalMs;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < glyphs.length; i++)
              () {
                final (opacity, dy) = _glyphAt(i, ms);
                return Opacity(
                  opacity: opacity,
                  child: Transform.translate(
                    offset: Offset(0, dy),
                    child: glyphs[i],
                  ),
                );
              }(),
          ],
        );
      },
    );
  }
}

/// A micro-label that swaps its text with a vertical slide, clipped to its own
/// slot so the change reads as one line replacing another.
///
/// Set [breathing] while the system is busy on a step that has no other motion
/// — the label then pulses gently to say the app has not stalled.
class SwapLabel extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final bool breathing;

  const SwapLabel({
    super.key,
    required this.text,
    this.style,
    this.breathing = false,
  });

  @override
  State<SwapLabel> createState() => _SwapLabelState();
}

class _SwapLabelState extends State<SwapLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
    value: 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncBreathing();
  }

  @override
  void didUpdateWidget(SwapLabel old) {
    super.didUpdateWidget(old);
    if (old.breathing != widget.breathing) _syncBreathing();
  }

  void _syncBreathing() {
    final wanted = widget.breathing && !reducedMotion(context);
    if (wanted && !_breathe.isAnimating) {
      _breathe.repeat(reverse: true);
    } else if (!wanted && _breathe.isAnimating) {
      _breathe
        ..stop()
        ..value = 1;
    }
  }

  @override
  void dispose() {
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final still = reducedMotion(context);

    final switcher = AnimatedSwitcher(
      // Asymmetric on purpose: the new state arrives gracefully, the old one
      // leaves promptly.
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 150),
      switchInCurve: Motion.enter,
      switchOutCurve: Motion.exit,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.centerLeft,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, anim) {
        final fade = FadeTransition(opacity: anim, child: child);
        if (still) return fade;
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.9),
            end: Offset.zero,
          ).animate(anim),
          child: fade,
        );
      },
      child: Text(
        widget.text,
        key: ValueKey(widget.text),
        style: widget.style,
      ),
    );

    return AnimatedBuilder(
      animation: _breathe,
      builder: (context, child) => Opacity(
        opacity: 0.5 + _breathe.value * 0.5,
        child: child,
      ),
      // ClipRect keeps the outgoing line inside the slot as it slides away.
      child: ClipRect(child: switcher),
    );
  }
}
