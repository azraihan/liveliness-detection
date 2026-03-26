import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pytorch_lite/flutter_pytorch_lite.dart';
import '../painters/face_frame_painter.dart';
import 'success_page.dart';

class LivenessPage extends StatefulWidget {
  const LivenessPage({super.key});
  @override
  State<LivenessPage> createState() => _LivenessPageState();
}

class _LivenessPageState extends State<LivenessPage>
    with TickerProviderStateMixin {
  // Camera & model
  CameraController? _camera;
  Module? _module;
  bool _cameraReady = false;
  bool _modelLoaded = false;
  bool _isProcessing = false;
  bool _isNavigating = false;

  // Inference state
  bool _hasResult = false;
  bool _isReal = false;
  bool _isSpoof = false;
  double _confidence = 0.0;

  Timer? _inferenceTimer;

  static const List<double> _mean = [0.485, 0.456, 0.406];
  static const List<double> _std  = [0.229, 0.224, 0.225];

  // Animations
  late final AnimationController _pulseCtrl;
  late final AnimationController _extCtrl;
  late final Animation<double> _pulseAnim;
  late final Animation<double> _extAnim;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initAll();
  }

  void _initAnimations() {
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1400))
      ..repeat(reverse: true);
    _pulseAnim = CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut);

    _extCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _extAnim = CurvedAnimation(parent: _extCtrl, curve: Curves.elasticOut);
    _extCtrl.forward();
  }

  Future<void> _initAll() async {
    await Future.wait([_loadModel(), _initCamera()]);
    if (mounted && _modelLoaded && _cameraReady) {
      _startInference();
    }
  }

  Future<void> _loadModel() async {
    try {
      final filePath = '${Directory.systemTemp.path}/mobilenetv2_mobile.ptl';
      final modelFile = File(filePath);
      if (!await modelFile.exists()) {
        final data = await rootBundle.load('assets/mobilenetv2_mobile.ptl');
        await modelFile.writeAsBytes(data.buffer.asUint8List());
      }
      _module = await FlutterPytorchLite.load(filePath);
      if (mounted) setState(() => _modelLoaded = true);
    } catch (e) {
      debugPrint('Model error: $e');
    }
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
          enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await _camera!.initialize();
      if (mounted) setState(() => _cameraReady = true);
    } catch (e) {
      debugPrint('Camera error: $e');
    }
  }

  void _startInference() {
    _inferenceTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) => _runInference());
  }

  Future<void> _runInference() async {
    if (!_modelLoaded || !_cameraReady || _isProcessing || _isNavigating) return;
    if (_camera == null || !_camera!.value.isInitialized || _module == null) return;

    _isProcessing = true;
    try {
      final XFile imageFile = await _camera!.takePicture();

      final imageProvider = FileImage(File(imageFile.path));
      final image = await TensorImageUtils.imageProviderToImage(imageProvider);

      // Get raw tensor (pixel values 0.0–1.0, NCHW: [1, 3, 224, 224])
      final Tensor rawTensor = await TensorImageUtils.imageToFloat32Tensor(
        image,
        width: 224,
        height: 224,
      );

      // Apply ImageNet normalization manually
      final Float32List rawData = rawTensor.dataAsFloat32List;
      const int pixelCount = 224 * 224;
      final Float32List normData = Float32List(3 * pixelCount);
      for (int c = 0; c < 3; c++) {
        final double m = _mean[c];
        final double s = _std[c];
        final int offset = c * pixelCount;
        for (int i = 0; i < pixelCount; i++) {
          normData[offset + i] = (rawData[offset + i] - m) / s;
        }
      }

      final Tensor inputTensor = Tensor.fromBlobFloat32(
        normData,
        Int64List.fromList([1, 3, 224, 224]),
      );

      final IValue output = await _module!.forward([IValue.from(inputTensor)]);
      final Float32List outputData = output.toTensor().dataAsFloat32List;

      double prob = 0.5;
      if (outputData.isNotEmpty) {
        prob = outputData[0].clamp(0.0, 1.0);
      }

      final bool isReal = prob > 0.5;
      final double confidence = isReal ? prob : (1 - prob);

      await File(imageFile.path).delete();

      if (mounted && !_isNavigating) {
        setState(() {
          _hasResult  = true;
          _isReal     = isReal;
          _isSpoof    = !isReal;
          _confidence = confidence;
        });

        if (isReal && confidence > 0.65) {
          _onRealDetected();
        }
      }
    } catch (e) {
      debugPrint('Inference error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  void _onRealDetected() {
    if (_isNavigating) return;
    _isNavigating = true;
    _inferenceTimer?.cancel();

    _extCtrl.reset();
    _extCtrl.forward();

    Future.delayed(const Duration(milliseconds: 900), () {
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
    _inferenceTimer?.cancel();
    _camera?.dispose();
    _module?.destroy();
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
            _buildStatusCard(),
            const SizedBox(height: 28),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
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
          const Text(
            'Face Verification',
            style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  // ── Camera section ────────────────────────────────────────────────────────
  Widget _buildCameraSection() {
    const cameraD    = 272.0;
    const containerD = 318.0;

    return Center(
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnim, _extAnim]),
        builder: (context, _) {
          FaceDirection dir;
          if (_isNavigating) {
            dir = FaceDirection.complete;
          } else {
            dir = FaceDirection.none;
          }

          return SizedBox(
            width: containerD,
            height: containerD,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Ambient glow when verified
                if (_isNavigating)
                  Container(
                    width: containerD,
                    height: containerD,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF00FF9D)
                              .withOpacity(0.05 + _pulseAnim.value * 0.05),
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
                    isComplete: _isNavigating,
                  ),
                ),

                // Camera preview inside circle
                ClipOval(
                  child: SizedBox(
                    width: cameraD,
                    height: cameraD,
                    child: Stack(
                      children: [
                        _buildCameraContent(),
                        // Scan line overlay
                        CustomPaint(
                          size: const Size(cameraD, cameraD),
                          painter: ScanLinePainter(_pulseAnim.value),
                        ),
                        // Edge vignette
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

  Widget _buildCameraContent() {
    if (_cameraReady && _camera != null) return CameraPreview(_camera!);
    return Container(
      color: const Color(0xFF0D1220),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.face_retouching_natural,
                color: Color(0xFF1A2640), size: 64),
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

  // ── Status card ───────────────────────────────────────────────────────────
  Widget _buildStatusCard() {
    final bool isInitializing = !_modelLoaded || !_cameraReady;

    Color  accentColor;
    IconData icon;
    String title;
    String subtitle;

    if (_isNavigating) {
      accentColor = const Color(0xFF00FF9D);
      icon        = Icons.check_circle_outline_rounded;
      title       = 'Face Verified!';
      subtitle    = 'Liveness confirmed — redirecting…';
    } else if (isInitializing) {
      accentColor = Colors.white38;
      icon        = Icons.hourglass_empty_rounded;
      title       = 'Initializing…';
      subtitle    = 'Setting up camera and model';
    } else if (_hasResult && _isSpoof) {
      accentColor = const Color(0xFFFF4D6D);
      icon        = Icons.warning_amber_rounded;
      title       = 'Spoof Detected';
      subtitle    =
          'Please use your real face · ${(_confidence * 100).toStringAsFixed(1)}% confident';
    } else {
      accentColor = const Color(0xFF00E5FF);
      icon        = Icons.radar_rounded;
      title       = _hasResult ? 'Scanning…' : 'Scanning…';
      subtitle    = _hasResult && _isReal
          ? 'Real face detected (${(_confidence * 100).toStringAsFixed(1)}%)'
          : 'Hold your face inside the circle';
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accentColor.withOpacity(0.25), width: 1),
          boxShadow: [
            BoxShadow(
              color: accentColor.withOpacity(0.07),
              blurRadius: 24,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: accentColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(icon, color: accentColor, size: 26),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    style: TextStyle(
                        color: accentColor,
                        fontSize: 15,
                        fontWeight: FontWeight.w700),
                    child: Text(title),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                        color: Colors.white.withOpacity(0.4),
                        fontSize: 12.5,
                        height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
