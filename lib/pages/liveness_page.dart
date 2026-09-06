import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pytorch_lite/flutter_pytorch_lite.dart';
import 'package:http/http.dart' as http;
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

  // Majority voting over a temporal window — one entry per analysed frame.
  static const int _maxSamples = 10;
  final List<({bool isReal, double confidence})> _samples = [];
  DateTime? _windowStart;

  // Inference state
  bool _hasResult = false;
  bool _isReal = false;
  bool _isSpoof = false;
  double _confidence = 0.0;

  // API second-layer state
  bool _isCallingApi = false;
  bool _isFinalFailure = false;

  static const String _apiUrl = 'http://168.144.41.182:8000/api/infer';

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

  /// Wall-clock seconds spanned by the current voting window.
  double get _elapsedSeconds => _windowStart == null
      ? 0
      : DateTime.now().difference(_windowStart!).inMilliseconds / 1000.0;

  void _startInference() {
    _inferenceTimer =
        Timer.periodic(const Duration(milliseconds: 500), (_) => _runInference());
  }

  Future<void> _runInference() async {
    if (!_modelLoaded || !_cameraReady || _isProcessing || _isNavigating) return;
    if (_isCallingApi || _isFinalFailure) return;
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
        _windowStart ??= DateTime.now();
        _samples.add((isReal: isReal, confidence: confidence));

        final int realCount  = _samples.where((s) => s.isReal).length;
        final int total      = _samples.length;

        setState(() {
          _hasResult  = true;
          _isReal     = isReal;
          _isSpoof    = !isReal;
          _confidence = confidence;
        });

        if (total >= _maxSamples) {
          final bool majorityReal = realCount > total ~/ 2;
          if (majorityReal) {
            _onRealDetected();
          } else {
            // Keep the window on screen — it's the evidence that triggered
            // the server escalation.
            _onLocalSpoofDetected();
          }
        }
      }
    } catch (e) {
      debugPrint('Inference error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  void _onLocalSpoofDetected() {
    if (_isNavigating || _isCallingApi || _isFinalFailure) return;
    _inferenceTimer?.cancel();
    setState(() => _isCallingApi = true);
    _callApiLayer();
  }

  Future<void> _callApiLayer() async {
    try {
      final XFile imageFile = await _camera!.takePicture();
      final bytes = await File(imageFile.path).readAsBytes();
      await File(imageFile.path).delete();

      final response = await http.post(
        Uri.parse(_apiUrl),
        headers: {'Content-Type': 'image/jpeg'},
        body: bytes,
      ).timeout(const Duration(minutes: 2));

      if (!mounted) return;

      debugPrint('API response: ${response.body}');

      if (response.statusCode == 200) {
        // Response is a JSON array; parse the first element
        final body = response.body.trim();
        // Extract is_real field manually to avoid adding dart:convert dependency
        final isRealMatch = RegExp(r'"is_real"\s*:\s*(true|false)').firstMatch(body);
        final isReal = isRealMatch?.group(1) == 'true';

        if (isReal) {
          setState(() => _isCallingApi = false);
          _onRealDetected();
        } else {
          setState(() {
            _isCallingApi  = false;
            _isFinalFailure = true;
            _isSpoof       = true;
            _hasResult     = true;
          });
        }
      } else {
        // Treat non-200 as final failure
        setState(() {
          _isCallingApi  = false;
          _isFinalFailure = true;
          _isSpoof       = true;
          _hasResult     = true;
        });
      }
    } catch (e) {
      debugPrint('API error: $e');
      if (mounted) {
        setState(() {
          _isCallingApi  = false;
          _isFinalFailure = true;
          _isSpoof       = true;
          _hasResult     = true;
        });
      }
    }
  }

  void _onRealDetected() {
    if (_isNavigating) return;
    _isNavigating = true;
    _samples.clear();
    _windowStart = null;
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
    } else if (_isFinalFailure) {
      accentColor = const Color(0xFFFF4D6D);
      icon        = Icons.block_rounded;
      title       = 'Spoof Detected';
      subtitle    = 'Liveness could not be confirmed. Please try again later.';
    } else if (_isCallingApi) {
      accentColor = const Color(0xFFFFB347);
      icon        = Icons.cloud_sync_rounded;
      title       = 'Double-Checking…';
      subtitle    = 'Running secondary verification via server';
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
      title       = _samples.isEmpty ? 'Scanning…' : 'Analysing Sequence…';
      subtitle    = _samples.isEmpty
          ? 'Hold your face inside the circle'
          : 'Frame ${_samples.length} of $_maxSamples · ${_elapsedSeconds.toStringAsFixed(1)}s observed';
    }

    // The strip is the evidence for the verdict, so show it while the window
    // is filling and while the server is adjudicating that same window.
    final bool showStrip =
        _samples.isNotEmpty && !_isNavigating && !isInitializing;

    // Motion coaching only helps while we're still collecting frames.
    final bool showHint = showStrip && !_isCallingApi && !_isFinalFailure;

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
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
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
            if (showHint) _buildMotionHint(accentColor),
            if (showStrip) _buildTemporalStrip(),
          ],
        ),
      ),
    );
  }

  // ── Motion prompt ─────────────────────────────────────────────────────────
  Widget _buildMotionHint(Color accentColor) {
    return Padding(
      padding: const EdgeInsets.only(top: 15),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        decoration: BoxDecoration(
          color: accentColor.withOpacity(0.08),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: accentColor.withOpacity(0.18)),
        ),
        child: Row(
          children: [
            Icon(Icons.gesture_rounded,
                color: accentColor.withOpacity(0.85), size: 16),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                'Move your face around a bit',
                style: TextStyle(
                  color: accentColor.withOpacity(0.9),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Temporal sample strip ─────────────────────────────────────────────────
  // One bar per analysed frame: height encodes that frame's confidence, colour
  // its verdict. Unfilled slots show how much of the window is still to come,
  // so the decision reads as a sequence rather than a single snapshot.
  Widget _buildTemporalStrip() {
    const green = Color(0xFF00FF9D);
    const red   = Color(0xFFFF4D6D);
    const empty = Color(0xFF1A2640);

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 36,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_maxSamples, (i) {
                final sample = i < _samples.length ? _samples[i] : null;
                final bool isNewest = sample != null && i == _samples.length - 1;
                final Color barColor =
                    sample == null ? empty : (sample.isReal ? green : red);

                // Confidence runs 0.5–1.0, so rescale it across the track.
                final double height = sample == null
                    ? 6
                    : 11 +
                        ((sample.confidence - 0.5) / 0.5).clamp(0.0, 1.0) * 25;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2.5),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      height: height,
                      decoration: BoxDecoration(
                        color: barColor.withOpacity(sample == null ? 0.35 : 0.9),
                        borderRadius: BorderRadius.circular(3),
                        boxShadow: isNewest
                            ? [
                                BoxShadow(
                                    color: barColor.withOpacity(0.55),
                                    blurRadius: 9)
                              ]
                            : null,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              Text(
                'TEMPORAL WINDOW',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.30),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                '${_samples.where((s) => s.isReal).length}/${_samples.length} live',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.30),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
