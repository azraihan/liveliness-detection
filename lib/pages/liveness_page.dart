import 'dart:async';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import '../painters/face_frame_painter.dart';
import 'success_page.dart';

// ─── Step model ──────────────────────────────────────────────────────────────

class _Step {
  final String title;
  final String subtitle;
  final FaceDirection direction;
  final IconData icon;
  const _Step({
    required this.title,
    required this.subtitle,
    required this.direction,
    required this.icon,
  });
}

const _steps = [
  _Step(
    title: 'Position your face',
    subtitle: 'Align your face inside the circle',
    direction: FaceDirection.none,
    icon: Icons.face_retouching_natural,
  ),
  _Step(
    title: 'Turn left slowly',
    subtitle: 'Rotate your head to the left',
    direction: FaceDirection.left,
    icon: Icons.arrow_back_rounded,
  ),
  _Step(
    title: 'Turn right slowly',
    subtitle: 'Rotate your head to the right',
    direction: FaceDirection.right,
    icon: Icons.arrow_forward_rounded,
  ),
  _Step(
    title: 'Look upward',
    subtitle: 'Tilt your chin slightly upward',
    direction: FaceDirection.up,
    icon: Icons.arrow_upward_rounded,
  ),
  _Step(
    title: 'Look downward',
    subtitle: 'Tilt your chin slightly downward',
    direction: FaceDirection.down,
    icon: Icons.arrow_downward_rounded,
  ),
];

// ─── Page ─────────────────────────────────────────────────────────────────────

class LivenessPage extends StatefulWidget {
  const LivenessPage({super.key});
  @override
  State<LivenessPage> createState() => _LivenessPageState();
}

class _LivenessPageState extends State<LivenessPage>
    with TickerProviderStateMixin {
  // Camera
  CameraController? _camera;
  bool _cameraReady = false;

  // Animations
  late final AnimationController _pulseCtrl;
  late final AnimationController _extCtrl;
  late final AnimationController _cardCtrl;

  late final Animation<double> _pulseAnim;
  late final Animation<double> _extAnim;
  late final Animation<double> _cardFade;
  late final Animation<Offset> _cardSlide;

  // State
  int _stepIndex = 0;
  bool _isComplete = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initCamera();
    _startSimulation();
  }

  void _initAnimations() {
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _extCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _extAnim =
        CurvedAnimation(parent: _extCtrl, curve: Curves.elasticOut);

    _cardCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 380));
    _cardFade =
        CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOut);
    _cardSlide = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _cardCtrl, curve: Curves.easeOutCubic));

    _cardCtrl.forward();
    _extCtrl.forward();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      _camera = CameraController(cam, ResolutionPreset.medium,
          enableAudio: false);
      await _camera!.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (_) {
      // Silently continue with placeholder if camera fails
    }
  }

  void _startSimulation() {
    _timer =
        Timer.periodic(const Duration(milliseconds: 2800), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_stepIndex < _steps.length - 1) {
        _advanceStep();
      } else {
        t.cancel();
        _finishVerification();
      }
    });
  }

  void _advanceStep() {
    _cardCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() => _stepIndex++);
      _extCtrl.reset();
      _extCtrl.forward();
      _cardCtrl.forward();
    });
  }

  void _finishVerification() {
    _cardCtrl.reverse().then((_) {
      if (!mounted) return;
      setState(() => _isComplete = true);
      _extCtrl.reset();
      _extCtrl.forward();
      _cardCtrl.forward();
    });
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, a, __) => const SuccessPage(),
          transitionsBuilder: (_, a, __, child) =>
              FadeTransition(opacity: a, child: child),
          transitionDuration: const Duration(milliseconds: 600),
        ),
      );
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _extCtrl.dispose();
    _cardCtrl.dispose();
    _timer?.cancel();
    _camera?.dispose();
    super.dispose();
  }

  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080C14),
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(child: _buildCameraSection()),
            _buildStepCard(),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final completed = _stepIndex + (_isComplete ? 1 : 0);
    final progress = completed / _steps.length;
    final progressColor =
        _isComplete ? const Color(0xFF00FF9D) : const Color(0xFF00E5FF);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 10),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFF111827),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: Colors.white54, size: 17),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Face Verification',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: const Color(0xFF1A2640),
                      valueColor:
                          AlwaysStoppedAnimation<Color>(progressColor),
                      minHeight: 3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Text(
            '$completed / ${_steps.length}',
            style: TextStyle(
                color: Colors.white.withOpacity(0.4),
                fontSize: 12,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ── Camera section ────────────────────────────────────────────────────────
  Widget _buildCameraSection() {
    const cameraD = 272.0;
    const containerD = 318.0;

    return Center(
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnim, _extAnim]),
        builder: (context, _) {
          final dir = _isComplete
              ? FaceDirection.complete
              : _steps[_stepIndex].direction;

          return SizedBox(
            width: containerD,
            height: containerD,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Background ambient glow
                if (_isComplete ||
                    _steps[_stepIndex].direction != FaceDirection.none)
                  Container(
                    width: containerD,
                    height: containerD,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: (_isComplete
                                  ? const Color(0xFF00FF9D)
                                  : const Color(0xFF00E5FF))
                              .withOpacity(
                                  0.05 + _pulseAnim.value * 0.04),
                          blurRadius: 60,
                          spreadRadius: 20,
                        ),
                      ],
                    ),
                  ),

                // Arc frame painter
                CustomPaint(
                  size: const Size(containerD, containerD),
                  painter: FaceFramePainter(
                    activeDirection: dir,
                    pulseValue: _pulseAnim.value,
                    arcExtension: _extAnim.value,
                    isComplete: _isComplete,
                  ),
                ),

                // Camera preview
                ClipOval(
                  child: SizedBox(
                    width: cameraD,
                    height: cameraD,
                    child: Stack(
                      children: [
                        _buildCameraContent(cameraD),
                        // Scan line overlay
                        CustomPaint(
                          size: const Size(cameraD, cameraD),
                          painter: ScanLinePainter(_pulseAnim.value),
                        ),
                        // Subtle dark vignette at edges
                        Container(
                          decoration: BoxDecoration(
                            gradient: RadialGradient(
                              center: Alignment.center,
                              radius: 0.9,
                              colors: [
                                Colors.transparent,
                                Colors.black.withOpacity(0.3),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildCameraContent(double size) {
    if (_cameraReady && _camera != null) {
      return CameraPreview(_camera!);
    }
    return Container(
      color: const Color(0xFF0D1220),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.face_retouching_natural,
                color: const Color(0xFF1A2640), size: 64),
            const SizedBox(height: 10),
            Text(
              'Camera initializing…',
              style: TextStyle(
                  color: const Color(0xFF1A2640).withOpacity(0.8),
                  fontSize: 11,
                  letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  // ── Step card ─────────────────────────────────────────────────────────────
  Widget _buildStepCard() {
    final step = _steps[_stepIndex];
    final accentColor =
        _isComplete ? const Color(0xFF00FF9D) : const Color(0xFF00E5FF);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: FadeTransition(
        opacity: _cardFade,
        child: SlideTransition(
          position: _cardSlide,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: accentColor.withOpacity(0.18),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: accentColor.withOpacity(0.06),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                // Icon container
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: accentColor.withOpacity(0.10),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    _isComplete
                        ? Icons.check_circle_outline_rounded
                        : step.icon,
                    color: accentColor,
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _isComplete ? 'All steps complete!' : step.title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _isComplete
                            ? 'Processing verification…'
                            : step.subtitle,
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.4),
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                // Progress dots
                _buildDots(accentColor),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDots(Color accentColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(_steps.length, (i) {
        final done = i < _stepIndex || _isComplete;
        final current = i == _stepIndex && !_isComplete;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 280),
          margin: const EdgeInsets.only(left: 4),
          width: current ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: done
                ? const Color(0xFF00FF9D)
                : current
                    ? accentColor
                    : const Color(0xFF1A2640),
          ),
        );
      }),
    );
  }
}
