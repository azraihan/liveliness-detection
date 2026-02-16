import 'dart:math';
import 'package:flutter/material.dart';
import 'liveness_page.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});
  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage>
    with TickerProviderStateMixin {
  late final AnimationController _rotCtrl;
  late final AnimationController _pulseCtrl;
  late final AnimationController _entryCtrl;

  late final Animation<double> _rotAnim;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _entryAnim;

  @override
  void initState() {
    super.initState();

    _rotCtrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 6))
      ..repeat();
    _rotAnim =
        Tween<double>(begin: 0, end: 2 * pi).animate(_rotCtrl);

    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _entryCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 900));
    _entryAnim =
        CurvedAnimation(parent: _entryCtrl, curve: Curves.easeOutCubic);
    _entryCtrl.forward();
  }

  @override
  void dispose() {
    _rotCtrl.dispose();
    _pulseCtrl.dispose();
    _entryCtrl.dispose();
    super.dispose();
  }

  void _goToLiveness() {
    Navigator.of(context).push(
      PageRouteBuilder(
        pageBuilder: (_, anim, __) => const LivenessPage(),
        transitionsBuilder: (_, anim, __, child) => SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(1.0, 0.0),
            end: Offset.zero,
          ).animate(CurvedAnimation(parent: anim, curve: Curves.easeOutCubic)),
          child: FadeTransition(opacity: anim, child: child),
        ),
        transitionDuration: const Duration(milliseconds: 480),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: FadeTransition(
          opacity: _entryAnim,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.04),
              end: Offset.zero,
            ).animate(_entryAnim),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 28),
                  _buildTopRow(),
                  const SizedBox(height: 44),
                  _buildHeroIcon(),
                  const SizedBox(height: 36),
                  _buildTitleBlock(),
                  const SizedBox(height: 36),
                  _buildChecklist(),
                  const Spacer(),
                  _buildStartButton(),
                  const SizedBox(height: 36),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Top row ───────────────────────────────────────────────────────────────
  Widget _buildTopRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFF00E5FF).withOpacity(0.25)),
            borderRadius: BorderRadius.circular(30),
            color: const Color(0xFF00E5FF).withOpacity(0.06),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _PulseDot(color: const Color(0xFF00E5FF)),
              const SizedBox(width: 8),
              const Text(
                'SECURE  ·  ENCRYPTED',
                style: TextStyle(
                  color: Color(0xFF00E5FF),
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        ),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: const Color(0xFF111827),
            borderRadius: BorderRadius.circular(11),
          ),
          child: const Icon(Icons.help_outline_rounded,
              color: Colors.white38, size: 18),
        ),
      ],
    );
  }

  // ── Animated hero icon ────────────────────────────────────────────────────
  Widget _buildHeroIcon() {
    return Center(
      child: AnimatedBuilder(
        animation: Listenable.merge([_rotAnim, _pulseAnim]),
        builder: (context, _) {
          return SizedBox(
            width: 180,
            height: 180,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Outer dashed ring – slow rotation
                Transform.rotate(
                  angle: _rotAnim.value,
                  child: CustomPaint(
                    size: const Size(176, 176),
                    painter: _DashedRingPainter(
                      color: const Color(0xFF00E5FF).withOpacity(0.25),
                      dashes: 24,
                    ),
                  ),
                ),
                // Middle ring – counter-rotation
                Transform.rotate(
                  angle: -_rotAnim.value * 0.55,
                  child: CustomPaint(
                    size: const Size(140, 140),
                    painter: _DashedRingPainter(
                      color: const Color(0xFF6C63FF).withOpacity(0.20),
                      dashes: 16,
                    ),
                  ),
                ),
                // Glow backdrop
                Container(
                  width: 100 + _pulseAnim.value * 6,
                  height: 100 + _pulseAnim.value * 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF00E5FF)
                            .withOpacity(0.12 + _pulseAnim.value * 0.08),
                        blurRadius: 30,
                        spreadRadius: 10,
                      ),
                    ],
                  ),
                ),
                // Core circle
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF0D1526),
                    border: Border.all(
                      color: const Color(0xFF00E5FF)
                          .withOpacity(0.35 + _pulseAnim.value * 0.15),
                      width: 1.5,
                    ),
                  ),
                  child: const Icon(
                    Icons.face_retouching_natural,
                    color: Color(0xFF00E5FF),
                    size: 42,
                  ),
                ),
                // Corner brackets
                ..._buildBrackets(),
              ],
            ),
          );
        },
      ),
    );
  }

  List<Widget> _buildBrackets() {
    const size = 168.0;
    const bSize = 14.0;
    const color = Color(0xFF00E5FF);
    final positions = [
      (top: 0.0, left: 0.0, rotate: 0.0),
      (top: 0.0, left: size - bSize, rotate: pi / 2),
      (top: size - bSize, left: 0.0, rotate: -pi / 2),
      (top: size - bSize, left: size - bSize, rotate: pi),
    ];
    return positions
        .map(
          (p) => Positioned(
            top: p.top,
            left: p.left,
            child: Transform.rotate(
              angle: p.rotate,
              child: CustomPaint(
                size: const Size(bSize, bSize),
                painter: _BracketPainter(color: color.withOpacity(0.55)),
              ),
            ),
          ),
        )
        .toList();
  }

  // ── Title block ───────────────────────────────────────────────────────────
  Widget _buildTitleBlock() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Verify Your\nIdentity',
          style: TextStyle(
            color: Colors.white,
            fontSize: 36,
            fontWeight: FontWeight.w800,
            height: 1.12,
            letterSpacing: -0.5,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'We'll use your camera to confirm it's really you. This check takes about 15 seconds.',
          style: TextStyle(
            color: Colors.white.withOpacity(0.42),
            fontSize: 14,
            height: 1.55,
            letterSpacing: 0.1,
          ),
        ),
      ],
    );
  }

  // ── Checklist ─────────────────────────────────────────────────────────────
  Widget _buildChecklist() {
    const items = [
      (Icons.wb_sunny_outlined, 'Good Lighting',
          'Face a window or lamp — no harsh backlighting'),
      (Icons.remove_red_eye_outlined, 'Eyes Visible',
          'Remove sunglasses or tinted lenses'),
      (Icons.sensors_rounded, 'Stay Still',
          'Move only when prompted on the next screen'),
    ];

    return Column(
      children: items
          .map((item) => _ChecklistRow(
                icon: item.$1,
                title: item.$2,
                subtitle: item.$3,
              ))
          .toList(),
    );
  }

  // ── Start button ──────────────────────────────────────────────────────────
  Widget _buildStartButton() {
    return GestureDetector(
      onTap: _goToLiveness,
      child: Container(
        width: double.infinity,
        height: 62,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF0099BB), Color(0xFF00E5FF)],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF00E5FF).withOpacity(0.28),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text(
              'Start Verification',
              style: TextStyle(
                color: Color(0xFF080C14),
                fontSize: 16,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: const Color(0xFF080C14).withOpacity(0.18),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.arrow_forward_rounded,
                color: Color(0xFF080C14),
                size: 17,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Small widgets ────────────────────────────────────────────────────────────

class _PulseDot extends StatefulWidget {
  final Color color;
  const _PulseDot({required this.color});
  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) => Container(
        width: 7,
        height: 7,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: widget.color.withOpacity(0.5 + _c.value * 0.5),
          boxShadow: [
            BoxShadow(
              color: widget.color.withOpacity(0.4 * _c.value),
              blurRadius: 6,
            ),
          ],
        ),
      ),
    );
  }
}

class _ChecklistRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  const _ChecklistRow(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Icon(icon, color: const Color(0xFF00E5FF), size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(
                          color: Colors.white.withOpacity(0.38),
                          fontSize: 12.5,
                          height: 1.4)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Painters ─────────────────────────────────────────────────────────────────

class _DashedRingPainter extends CustomPainter {
  final Color color;
  final int dashes;
  const _DashedRingPainter({required this.color, required this.dashes});

  @override
  void paint(Canvas canvas, Size size) {
    final radius = min(size.width, size.height) / 2 - 1;
    final center = Offset(size.width / 2, size.height / 2);
    const gapRatio = 0.45;
    final dashSweep = (2 * pi / dashes) * (1 - gapRatio);

    for (int i = 0; i < dashes; i++) {
      final start = i * 2 * pi / dashes;
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        dashSweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5
          ..strokeCap = StrokeCap.round,
      );
    }
  }

  @override
  bool shouldRepaint(_DashedRingPainter old) => false;
}

class _BracketPainter extends CustomPainter {
  final Color color;
  const _BracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final s = size.width;
    canvas.drawLine(Offset(0, s), const Offset(0, 0), p);
    canvas.drawLine(const Offset(0, 0), Offset(s, 0), p);
  }

  @override
  bool shouldRepaint(_BracketPainter old) => false;
}
