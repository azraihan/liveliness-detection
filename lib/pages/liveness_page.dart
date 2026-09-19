import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pytorch_lite/flutter_pytorch_lite.dart';
// Server-side second opinion is disabled for now — see _callApiLayer below.
// import 'package:http/http.dart' as http;
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

  // ── Model contract (assets/models/model_contract.json) ───────────────────
  // Input : float32 [1, 24, 3, 224, 224], layout N-K-C-H-W, RGB
  // Output: float32 [1, 2] raw logits — index 0 = real, index 1 = fake
  static const String _modelAsset = 'assets/models/mobilenetv3_temporal_k24.ptl';
  static const int _clipFrames    = 24;
  static const int _inputSize     = 224;
  static const int _pixelsPerFrame = _inputSize * _inputSize;   //    50,176
  static const int _floatsPerFrame = 3 * _pixelsPerFrame;       //   150,528
  static const int _clipFloats = _clipFrames * _floatsPerFrame; // 3,612,672

  /// One clip's input tensor, allocated once and refilled per clip (~13.8 MiB).
  final Float32List _clipBuffer = Float32List(_clipFloats);
  int _framesCollected = 0;
  DateTime? _windowStart;

  // Inference state
  bool _hasResult = false;
  bool _isSpoof = false;
  double _confidence = 0.0; // probability of the winning class

  // ── API second-layer state — disabled for now, kept for later ────────────
  // bool _isCallingApi = false;
  // bool _isFinalFailure = false;
  // static const String _apiUrl = 'http://168.144.41.182:8000/api/infer';

  bool _isCollecting = false;
  Timer? _restartTimer;

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
      final filePath =
          '${Directory.systemTemp.path}/mobilenetv3_temporal_k24.ptl';
      final modelFile = File(filePath);
      if (!await modelFile.exists()) {
        final data = await rootBundle.load(_modelAsset);
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

  /// Wall-clock seconds spanned by the clip being collected.
  double get _elapsedSeconds => _windowStart == null
      ? 0
      : DateTime.now().difference(_windowStart!).inMilliseconds / 1000.0;

  // ── Clip collection ───────────────────────────────────────────────────────
  // The model consumes 24 consecutive frames per call, so frames are gathered
  // back-to-back (not on a fixed timer) to keep the clip as short in real time
  // as the device allows, then handed to the model as one tensor.

  void _startInference() => _collectClip();

  Future<void> _collectClip() async {
    if (_isCollecting || _isNavigating || !mounted) return;
    _isCollecting = true;

    setState(() {
      _framesCollected = 0;
      _windowStart = DateTime.now();
      _hasResult = false;
    });

    try {
      while (_framesCollected < _clipFrames) {
        if (!mounted || _isNavigating) return;
        if (_camera == null || !_camera!.value.isInitialized) return;

        await _captureFrameInto(_framesCollected);
        if (!mounted || _isNavigating) return;
        setState(() => _framesCollected++);
      }
      await _runClipInference();
    } catch (e) {
      debugPrint('Clip error: $e');
    } finally {
      _isCollecting = false;
    }
  }

  /// Captures one frame and writes it, preprocessed, into slot [k] of the clip
  /// buffer. Crop, scale, RGB extraction and ImageNet normalisation are fused
  /// into a single pass so no intermediate 150k-element list is built per frame.
  Future<void> _captureFrameInto(int k) async {
    final XFile shot = await _camera!.takePicture();
    try {
      final Uint8List jpeg = await File(shot.path).readAsBytes();
      final ui.Codec codec = await ui.instantiateImageCodec(jpeg);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image src = frame.image;

      final ui.Image square = await _centerCropResize(src, _inputSize);
      src.dispose();
      codec.dispose();

      final ByteData? rgba =
          await square.toByteData(format: ui.ImageByteFormat.rawRgba);
      square.dispose();
      if (rgba == null) return;

      final Uint8List px = rgba.buffer.asUint8List();
      final int base = k * _floatsPerFrame;
      final double mR = _mean[0], mG = _mean[1], mB = _mean[2];
      final double sR = _std[0],  sG = _std[1],  sB = _std[2];

      // Planar RGB: all R, then all G, then all B — the C dimension of N-K-C-H-W.
      for (int p = 0; p < _pixelsPerFrame; p++) {
        final int o = p * 4;
        _clipBuffer[base + p] = (px[o] / 255.0 - mR) / sR;
        _clipBuffer[base + _pixelsPerFrame + p] =
            (px[o + 1] / 255.0 - mG) / sG;
        _clipBuffer[base + 2 * _pixelsPerFrame + p] =
            (px[o + 2] / 255.0 - mB) / sB;
      }
    } finally {
      try {
        await File(shot.path).delete();
      } catch (_) {/* best effort */}
    }
  }

  /// Center-crops the largest square from [src] and scales it to [size]².
  Future<ui.Image> _centerCropResize(ui.Image src, int size) async {
    final double side = math.min(src.width, src.height).toDouble();
    final double dx = (src.width - side) / 2;
    final double dy = (src.height - side) / 2;

    final recorder = ui.PictureRecorder();
    ui.Canvas(recorder).drawImageRect(
      src,
      ui.Rect.fromLTWH(dx, dy, side, side),
      ui.Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
      ui.Paint()..filterQuality = FilterQuality.high,
    );
    final ui.Picture picture = recorder.endRecording();
    final ui.Image out = await picture.toImage(size, size);
    picture.dispose();
    return out;
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  Future<void> _runClipInference() async {
    if (_module == null || _isNavigating || !mounted) return;

    _isProcessing = true;
    try {
      final Tensor input = Tensor.fromBlobFloat32(
        _clipBuffer,
        Int64List.fromList([1, _clipFrames, 3, _inputSize, _inputSize]),
      );

      final IValue output = await _module!.forward([IValue.from(input)]);
      final Float32List logits = output.toTensor().dataAsFloat32List;
      if (logits.length < 2 || !mounted) return;

      // Raw logits — index 0 real, index 1 fake. Numerically stable softmax.
      final double realLogit = logits[0];
      final double fakeLogit = logits[1];
      final double m = math.max(realLogit, fakeLogit);
      final double realExp = math.exp(realLogit - m);
      final double fakeExp = math.exp(fakeLogit - m);
      final double pFake = fakeExp / (realExp + fakeExp);

      debugPrint('logits: real=$realLogit fake=$fakeLogit  pFake=$pFake');

      final bool isReal = pFake < 0.5;

      setState(() {
        _hasResult  = true;
        _isSpoof    = !isReal;
        _confidence = isReal ? (1 - pFake) : pFake;
      });

      if (isReal) {
        _onRealDetected();
      } else {
        _onSpoofDetected();
      }
    } catch (e) {
      debugPrint('Inference error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  /// No server fallback for now, so a spoof verdict simply shows, then a fresh
  /// clip starts — the user is never stuck on a dead end.
  void _onSpoofDetected() {
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 3500), () {
      if (!mounted || _isNavigating) return;
      _collectClip();
    });
  }

  // ── Server second opinion — disabled for now, kept for later ──────────────
  //
  // void _onLocalSpoofDetected() {
  //   if (_isNavigating || _isCallingApi || _isFinalFailure) return;
  //   setState(() => _isCallingApi = true);
  //   _callApiLayer();
  // }
  //
  // Future<void> _callApiLayer() async {
  //   try {
  //     final XFile imageFile = await _camera!.takePicture();
  //     final bytes = await File(imageFile.path).readAsBytes();
  //     await File(imageFile.path).delete();
  //
  //     final response = await http.post(
  //       Uri.parse(_apiUrl),
  //       headers: {'Content-Type': 'image/jpeg'},
  //       body: bytes,
  //     ).timeout(const Duration(minutes: 2));
  //
  //     if (!mounted) return;
  //     debugPrint('API response: ${response.body}');
  //
  //     if (response.statusCode == 200) {
  //       final body = response.body.trim();
  //       final isRealMatch =
  //           RegExp(r'"is_real"\s*:\s*(true|false)').firstMatch(body);
  //       final isReal = isRealMatch?.group(1) == 'true';
  //
  //       if (isReal) {
  //         setState(() => _isCallingApi = false);
  //         _onRealDetected();
  //       } else {
  //         setState(() {
  //           _isCallingApi   = false;
  //           _isFinalFailure = true;
  //           _isSpoof        = true;
  //           _hasResult      = true;
  //         });
  //       }
  //     } else {
  //       setState(() {
  //         _isCallingApi   = false;
  //         _isFinalFailure = true;
  //         _isSpoof        = true;
  //         _hasResult      = true;
  //       });
  //     }
  //   } catch (e) {
  //     debugPrint('API error: $e');
  //     if (mounted) {
  //       setState(() {
  //         _isCallingApi   = false;
  //         _isFinalFailure = true;
  //         _isSpoof        = true;
  //         _hasResult      = true;
  //       });
  //     }
  //   }
  // }

  void _onRealDetected() {
    if (_isNavigating) return;
    _isNavigating = true;
    _restartTimer?.cancel();

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
    _restartTimer?.cancel();
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

    final bool clipFull = _framesCollected >= _clipFrames;

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
          'Not a live face · ${(_confidence * 100).toStringAsFixed(1)}% confident · retrying…';
    } else if (clipFull && _isProcessing) {
      accentColor = const Color(0xFFFFB347);
      icon        = Icons.memory_rounded;
      title       = 'Running Model…';
      subtitle    = 'Analysing all $_clipFrames frames together';
    } else {
      accentColor = const Color(0xFF00E5FF);
      icon        = Icons.radar_rounded;
      title       = _framesCollected == 0 ? 'Scanning…' : 'Recording Sequence…';
      subtitle    = _framesCollected == 0
          ? 'Hold your face inside the circle'
          : 'Frame $_framesCollected of $_clipFrames · ${_elapsedSeconds.toStringAsFixed(1)}s recorded';
    }

    final bool showStrip = _framesCollected > 0 && !_isNavigating && !isInitializing;

    // Motion coaching only helps while we're still collecting frames.
    final bool showHint = showStrip && !clipFull && !(_hasResult && _isSpoof);

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

  // ── Temporal clip strip ───────────────────────────────────────────────────
  // One bar per frame in the 24-frame clip. Unlike the old per-frame model,
  // there is no verdict until the whole clip runs, so the bars show the
  // sequence being recorded and then all flash the result together.
  Widget _buildTemporalStrip() {
    const green = Color(0xFF00FF9D);
    const red   = Color(0xFFFF4D6D);
    const cyan  = Color(0xFF00E5FF);
    const empty = Color(0xFF1A2640);

    final bool hasVerdict = _hasResult;
    final Color filledColor =
        hasVerdict ? (_isSpoof ? red : green) : cyan;

    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 34,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: List.generate(_clipFrames, (i) {
                final bool filled = i < _framesCollected;
                final bool isNewest = filled && i == _framesCollected - 1;

                // A gentle standing wave keeps the recorded run alive-looking
                // without implying a per-frame score the model never produces.
                final double height = filled
                    ? 13 + math.sin(i * 0.7 + _pulseAnim.value * math.pi) * 5
                    : 6;

                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.2),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      height: height,
                      decoration: BoxDecoration(
                        color: filled
                            ? filledColor.withOpacity(0.9)
                            : empty.withOpacity(0.35),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: isNewest
                            ? [
                                BoxShadow(
                                    color: filledColor.withOpacity(0.55),
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
                'TEMPORAL CLIP · K=$_clipFrames',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.30),
                  fontSize: 9,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                ),
              ),
              const Spacer(),
              Text(
                hasVerdict
                    ? (_isSpoof ? 'SPOOF' : 'LIVE')
                    : '$_framesCollected/$_clipFrames',
                style: TextStyle(
                  color: hasVerdict
                      ? filledColor.withOpacity(0.75)
                      : Colors.white.withOpacity(0.30),
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
