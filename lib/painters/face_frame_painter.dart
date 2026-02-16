import 'dart:math';
import 'package:flutter/material.dart';

enum FaceDirection { none, left, right, up, down, complete }

// ─── Main painter ─────────────────────────────────────────────────────────────

class FaceFramePainter extends CustomPainter {
  final FaceDirection activeDirection;
  final double pulseValue; // 0.0 – 1.0
  final double arcExtension; // 0.0 – 1.0
  final bool isComplete;

  const FaceFramePainter({
    required this.activeDirection,
    required this.pulseValue,
    this.arcExtension = 1.0,
    this.isComplete = false,
  });

  static const _cyan  = Color(0xFF00E5FF);
  static const _green = Color(0xFF00FF9D);

  Color get _activeColor => isComplete ? _green : _cyan;

  // 60 small segments evenly distributed around the circle
  static const int _totalSegments = 60;

  // Angular half-width of one direction's active zone (degrees)
  static const double _zoneHalfDeg = 48.0;

  // Map direction → centre angle in degrees (0° = 3 o'clock, clockwise)
  static double _directionCenter(FaceDirection dir) {
    switch (dir) {
      case FaceDirection.right: return 0.0;
      case FaceDirection.down:  return 90.0;
      case FaceDirection.left:  return 180.0;
      case FaceDirection.up:    return 270.0;
      default:                  return 0.0;
    }
  }

  // Returns how far (0 = centre of zone → 1 = edge) a given angle is
  // within the active zone, or null if outside.
  double? _zoneProgress(double angleDeg, FaceDirection dir) {
    final center = _directionCenter(dir);
    double diff = ((angleDeg - center) % 360 + 360) % 360;
    if (diff > 180) diff = 360 - diff;
    if (diff > _zoneHalfDeg) return null;
    return diff / _zoneHalfDeg; // 0 = hot centre, 1 = cool edge
  }

  // Layered wave function — produces a varied, organic extension length
  // so each segment in the active zone extends to a different height.
  double _waveExtension(double zonePos, int segIdx, double pulse) {
    // Smooth cosine envelope: full at centre, zero at edges
    final envelope = cos(zonePos * pi / 2); // 1.0 → 0.0

    // Multiple interfering waves create organic, non-uniform shapes
    final w1 = sin(zonePos * pi * 2.2 + pulse * pi * 2.0)          * 8.0;
    final w2 = sin(zonePos * pi * 5.5 + segIdx  * 0.55)             * 4.5;
    final w3 = cos(zonePos * pi * 8.0 + pulse * pi * 1.4 + 1.2)     * 3.0;
    // Per-segment "noise" — makes every segment subtly unique
    final w4 = sin(segIdx  * 1.17 + pulse * pi * 0.8)               * 2.5;

    final wave = (10.0 + w1 + w2 + w3 + w4).clamp(2.0, 26.0);
    return wave * envelope * arcExtension;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2 - 14.0;

    // Faint ghost circle inside the segments
    canvas.drawCircle(
      center,
      radius - 4,
      Paint()
        ..color = Colors.white.withOpacity(0.025)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );

    for (int i = 0; i < _totalSegments; i++) {
      final angleDeg = i * 360.0 / _totalSegments;
      final angleRad = angleDeg * pi / 180.0;

      // ── Idle state: all segments breathe softly, no extension ─────────
      if (activeDirection == FaceDirection.none && !isComplete) {
        _paintSegment(
          canvas: canvas, center: center, radius: radius, angleRad: angleRad,
          length: 4.5 + pulseValue * 1.8,
          color: _cyan.withOpacity(0.10 + pulseValue * 0.07),
          width: 2.2,
          glowBlur: 0,
        );
        continue;
      }

      // ── Determine this segment's zone membership ───────────────────────
      double? zp;
      if (isComplete) {
        // All segments active simultaneously for the success flash
        zp = 0.0;
      } else {
        zp = _zoneProgress(angleDeg, activeDirection);
      }

      if (zp == null) {
        // Inactive segment — dim background tick
        _paintSegment(
          canvas: canvas, center: center, radius: radius, angleRad: angleRad,
          length: 4.0,
          color: const Color(0xFF1A2640).withOpacity(0.45),
          width: 1.8,
          glowBlur: 0,
        );
        continue;
      }

      // ── Active segment ─────────────────────────────────────────────────
      final ext = isComplete
          ? _waveExtension(zp, i, pulseValue) * 0.65
          : _waveExtension(zp, i, pulseValue);

      // Fade out towards zone edges
      final edgeFade = isComplete ? 1.0 : (1.0 - zp * zp * 0.45).clamp(0.55, 1.0);

      final totalLen = 5.5 + ext;

      // Layer 1 — wide soft halo
      _paintSegment(
        canvas: canvas, center: center, radius: radius, angleRad: angleRad,
        length: totalLen,
        color: _activeColor.withOpacity(0.10 * edgeFade),
        width: 11,
        glowBlur: 9,
      );
      // Layer 2 — mid glow
      _paintSegment(
        canvas: canvas, center: center, radius: radius, angleRad: angleRad,
        length: totalLen,
        color: _activeColor.withOpacity(0.35 * edgeFade),
        width: 4.5,
        glowBlur: 4,
      );
      // Layer 3 — sharp core
      _paintSegment(
        canvas: canvas, center: center, radius: radius, angleRad: angleRad,
        length: totalLen,
        color: _activeColor.withOpacity(edgeFade),
        width: 2.2,
        glowBlur: 0,
      );
      // Layer 4 — bright white tip (short, positioned at top of segment)
      _paintSegment(
        canvas: canvas,
        center: center,
        radius: radius + 4.0 + ext * 0.80, // floats near the tip
        angleRad: angleRad,
        length: 2.5,
        color: Colors.white.withOpacity((0.5 + pulseValue * 0.25) * edgeFade),
        width: 1.2,
        glowBlur: 0,
      );
    }
  }

  /// Draws one radially-oriented rounded segment as a line.
  void _paintSegment({
    required Canvas canvas,
    required Offset center,
    required double radius,
    required double angleRad,
    required double length,
    required Color color,
    required double width,
    required double glowBlur,
  }) {
    if (length <= 0) return;
    const gap = 3.5; // spacing between circle edge and segment root
    final r0 = radius + gap;
    final r1 = r0 + length;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round;

    if (glowBlur > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, glowBlur);
    }

    canvas.drawLine(
      Offset(center.dx + cos(angleRad) * r0, center.dy + sin(angleRad) * r0),
      Offset(center.dx + cos(angleRad) * r1, center.dy + sin(angleRad) * r1),
      paint,
    );
  }

  @override
  bool shouldRepaint(FaceFramePainter old) =>
      old.activeDirection != activeDirection ||
      old.pulseValue   != pulseValue   ||
      old.arcExtension != arcExtension ||
      old.isComplete   != isComplete;
}

// ─── Scan-line painter used inside camera circle ──────────────────────────────
class ScanLinePainter extends CustomPainter {
  final double progress; // 0.0 – 1.0
  const ScanLinePainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height * progress;
    canvas.drawRect(
      Rect.fromLTWH(0, y - 18, size.width, 36),
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            const Color(0xFF00E5FF).withOpacity(0.07),
            Colors.transparent,
          ],
        ).createShader(Rect.fromLTWH(0, 0, size.width, size.height)),
    );
  }

  @override
  bool shouldRepaint(ScanLinePainter old) => old.progress != progress;
}
