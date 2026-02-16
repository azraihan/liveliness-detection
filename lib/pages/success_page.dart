import 'package:flutter/material.dart';

class SuccessPage extends StatefulWidget {
  const SuccessPage({super.key});
  @override
  State<SuccessPage> createState() => _SuccessPageState();
}

class _SuccessPageState extends State<SuccessPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  // Staggered sub-animations
  late final Animation<double> _scaleBadge;
  late final Animation<double> _fadeContent;
  late final Animation<double> _ring1;
  late final Animation<double> _ring2;
  late final Animation<double> _ring3;
  late final Animation<double> _slideContent;

  static const _green = Color(0xFF00FF9D);

  @override
  void initState() {
    super.initState();

    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );

    _scaleBadge = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.0, 0.55, curve: Curves.elasticOut)),
    );

    _ring1 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.2, 0.75, curve: Curves.easeOut)),
    );
    _ring2 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.35, 0.90, curve: Curves.easeOut)),
    );
    _ring3 = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.50, 1.0, curve: Curves.easeOut)),
    );

    _fadeContent = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.55, 1.0, curve: Curves.easeOut)),
    );
    _slideContent = Tween<double>(begin: 24.0, end: 0.0).animate(
      CurvedAnimation(
          parent: _ctrl,
          curve: const Interval(0.55, 1.0, curve: Curves.easeOutCubic)),
    );

    _ctrl.forward();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Center(
          child: AnimatedBuilder(
            animation: _ctrl,
            builder: (context, _) {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildIconSection(),
                  const SizedBox(height: 52),
                  _buildTextSection(),
                  const SizedBox(height: 52),
                  _buildCTAButton(context),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  // ── Animated icon with expanding rings ────────────────────────────────────
  Widget _buildIconSection() {
    return SizedBox(
      width: 240,
      height: 240,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ring 3 – outermost, fades out as it expands
          _AnimatedRing(
            progress: _ring3.value,
            baseRadius: 75,
            color: _green,
            opacity: (1.0 - _ring3.value) * 0.18,
            strokeWidth: 1.0,
          ),
          // Ring 2
          _AnimatedRing(
            progress: _ring2.value,
            baseRadius: 64,
            color: _green,
            opacity: (1.0 - _ring2.value) * 0.28,
            strokeWidth: 1.2,
          ),
          // Ring 1 – closest
          _AnimatedRing(
            progress: _ring1.value,
            baseRadius: 52,
            color: _green,
            opacity: (1.0 - _ring1.value) * 0.40,
            strokeWidth: 1.5,
          ),
          // Core badge
          Transform.scale(
            scale: _scaleBadge.value,
            child: Container(
              width: 110,
              height: 110,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _green.withOpacity(0.10),
                border: Border.all(color: _green, width: 2),
                boxShadow: [
                  BoxShadow(
                    color: _green.withOpacity(0.25),
                    blurRadius: 40,
                    spreadRadius: 8,
                  ),
                  BoxShadow(
                    color: _green.withOpacity(0.12),
                    blurRadius: 80,
                    spreadRadius: 20,
                  ),
                ],
              ),
              child: const Icon(Icons.check_rounded, color: _green, size: 56),
            ),
          ),
        ],
      ),
    );
  }

  // ── Text content ─────────────────────────────────────────────────────────
  Widget _buildTextSection() {
    return Opacity(
      opacity: _fadeContent.value,
      child: Transform.translate(
        offset: Offset(0, _slideContent.value),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            children: [
              const Text(
                'Identity Verified',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Your face has been successfully authenticated. You're all set to continue.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.40),
                  fontSize: 14,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 20),
              // Verified pill badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  color: _green.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: _green.withOpacity(0.25)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.verified_rounded,
                        color: _green, size: 15),
                    const SizedBox(width: 7),
                    const Text(
                      'Liveness Check Passed',
                      style: TextStyle(
                        color: _green,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── CTA button ───────────────────────────────────────────────────────────
  Widget _buildCTAButton(BuildContext context) {
    return Opacity(
      opacity: _fadeContent.value,
      child: Transform.translate(
        offset: Offset(0, _slideContent.value * 1.5),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: GestureDetector(
            onTap: () =>
                Navigator.of(context).popUntil((r) => r.isFirst),
            child: Container(
              width: double.infinity,
              height: 60,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF00CC7A), Color(0xFF00FF9D)],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: _green.withOpacity(0.28),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Center(
                child: Text(
                  'Continue',
                  style: TextStyle(
                    color: Color(0xFF080C14),
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Animated expanding ring ─────────────────────────────────────────────────

class _AnimatedRing extends StatelessWidget {
  final double progress; // 0.0 – 1.0
  final double baseRadius;
  final Color color;
  final double opacity;
  final double strokeWidth;

  const _AnimatedRing({
    required this.progress,
    required this.baseRadius,
    required this.color,
    required this.opacity,
    required this.strokeWidth,
  });

  @override
  Widget build(BuildContext context) {
    final radius = baseRadius + progress * baseRadius * 0.8;
    final d = radius * 2;
    return Container(
      width: d,
      height: d,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: color.withOpacity(opacity.clamp(0.0, 1.0)),
          width: strokeWidth,
        ),
      ),
    );
  }
}
