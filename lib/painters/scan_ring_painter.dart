import 'dart:math' as math;
import 'package:flutter/material.dart';

/// The ring around the camera. A hairline track with one arc drawn on top —
/// determinate while frames are being collected, a short orbiting sweep while
/// the model runs, closed when there is a verdict.
class ScanRingPainter extends CustomPainter {
  /// 0–1 share of the clip collected. Ignored when [indeterminate].
  final double progress;

  /// 0–1 rotation phase, only read when [indeterminate].
  final double spin;

  final bool indeterminate;
  final Color trackColor;
  final Color arcColor;
  final double inset;

  const ScanRingPainter({
    required this.progress,
    required this.spin,
    required this.indeterminate,
    required this.trackColor,
    required this.arcColor,
    this.inset = 1.0,
  });

  static const _startAngle = -math.pi / 2; // 12 o'clock

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - inset;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = trackColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final arc = Paint()
      ..color = arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    if (indeterminate) {
      // A 70° sweep chasing the ring — reads as "working", not as progress.
      const sweep = math.pi * 70 / 180;
      canvas.drawArc(rect, _startAngle + spin * 2 * math.pi, sweep, false, arc);
      return;
    }

    if (progress <= 0) return;
    canvas.drawArc(
      rect,
      _startAngle,
      (progress.clamp(0.0, 1.0)) * 2 * math.pi,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(ScanRingPainter old) =>
      old.progress != progress ||
      old.spin != spin ||
      old.indeterminate != indeterminate ||
      old.trackColor != trackColor ||
      old.arcColor != arcColor;
}

/// A single soft band travelling down the preview. One hairline, very low
/// alpha — enough to say "live capture", not enough to be scenery.
class ScanSweepPainter extends CustomPainter {
  final double progress; // 0–1, top to bottom
  final Color color;

  const ScanSweepPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    const band = 64.0;

    final rect = Rect.fromLTWH(0, y - band / 2, size.width, band);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            color.withValues(alpha: 0),
            color.withValues(alpha: 0.10),
            color.withValues(alpha: 0),
          ],
        ).createShader(rect),
    );

    canvas.drawLine(
      Offset(0, y),
      Offset(size.width, y),
      Paint()
        ..color = color.withValues(alpha: 0.16)
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(ScanSweepPainter old) =>
      old.progress != progress || old.color != color;
}

/// The landing screen's mark: a hairline circle with one dot in slow orbit.
class OrbitMarkPainter extends CustomPainter {
  final double phase; // 0–1
  final Color ringColor;
  final Color dotColor;

  const OrbitMarkPainter({
    required this.phase,
    required this.ringColor,
    required this.dotColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - 3;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    final angle = -math.pi / 2 + phase * 2 * math.pi;
    canvas.drawCircle(
      center + Offset(math.cos(angle) * radius, math.sin(angle) * radius),
      3,
      Paint()..color = dotColor,
    );
  }

  @override
  bool shouldRepaint(OrbitMarkPainter old) =>
      old.phase != phase ||
      old.ringColor != ringColor ||
      old.dotColor != dotColor;
}

/// Draws a checkmark stroke-first, so the success screen resolves with a
/// gesture rather than a pop.
class CheckPainter extends CustomPainter {
  final double progress; // 0–1 of the stroke drawn
  final Color color;

  const CheckPainter({required this.progress, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0) return;

    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(w * 0.20, h * 0.52)
      ..lineTo(w * 0.42, h * 0.72)
      ..lineTo(w * 0.80, h * 0.28);

    final metrics = path.computeMetrics().toList();
    final drawn = Path();
    for (final m in metrics) {
      drawn.addPath(m.extractPath(0, m.length * progress), Offset.zero);
    }

    canvas.drawPath(
      drawn,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(CheckPainter old) =>
      old.progress != progress || old.color != color;
}

/// The band of short radial ticks just outside the ring, shown only while a
/// clip is being captured — the moment the user is asked to move a little.
///
/// A slow travelling wave runs around the circle so the ticks read as motion
/// *around* the face rather than a uniform throb. [amplitude] is an envelope
/// that fades the whole band in and out, so it never pops on a state change.
///
/// Both animations are passed straight to `super.repaint`: the painter
/// repaints on its own without rebuilding any widgets above it.
class CaptureTicksPainter extends CustomPainter {
  /// 0–1, linear and looping. Drives the wave's rotation.
  final Animation<double> phase;

  /// 0–1. Scales every tick's length and opacity; 0 draws nothing.
  final Animation<double> amplitude;

  final Color color;

  /// Distance from the box edge to the ring track, i.e. the band the ticks
  /// live in. Matches the ring painter's own inset.
  final double inset;

  /// When true the wave holds still and the ticks sit at their mean length.
  final bool still;

  CaptureTicksPainter({
    required this.phase,
    required this.amplitude,
    required this.color,
    required this.inset,
    required this.still,
  }) : super(repaint: Listenable.merge([phase, amplitude]));

  static const int _count = 72;

  /// Crests around the circle. Three reads as movement; more reads as noise.
  static const double _crests = 3;

  static const double _gap = 5.0; // clearance between track and tick root
  static const double _restLength = 3.0;
  static const double _travel = 9.0; // extra length at a crest

  @override
  void paint(Canvas canvas, Size size) {
    final amp = amplitude.value;
    if (amp <= 0.01) return;

    final center = Offset(size.width / 2, size.height / 2);
    final ringRadius = math.min(size.width, size.height) / 2 - inset;
    final t = phase.value * 2 * math.pi;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < _count; i++) {
      final theta = i * 2 * math.pi / _count - math.pi / 2;

      // 0–1, peaking at the crests. Held at its mean under reduced motion.
      final wave =
          still ? 0.5 : 0.5 + 0.5 * math.sin(theta * _crests - t);

      final length = (_restLength + wave * _travel) * amp;
      final r0 = ringRadius + _gap;
      final r1 = r0 + length;

      paint.color = color.withValues(alpha: (0.16 + wave * 0.30) * amp);

      final dx = math.cos(theta);
      final dy = math.sin(theta);
      canvas.drawLine(
        Offset(center.dx + dx * r0, center.dy + dy * r0),
        Offset(center.dx + dx * r1, center.dy + dy * r1),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(CaptureTicksPainter old) =>
      old.color != color || old.inset != inset || old.still != still;
}
