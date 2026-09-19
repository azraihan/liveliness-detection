import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_pytorch_lite/flutter_pytorch_lite.dart';
// Server-side second opinion is disabled for now — see _callApiLayer below.
// import 'package:http/http.dart' as http;
import '../painters/scan_ring_painter.dart';
import '../services/liveness_model.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_label.dart';
import '../widgets/fade_rise.dart';
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
  /// Softmax probability of the "real" class for the last clip — the liveness
  /// score itself, not the winning class's probability. Once the decision uses
  /// a threshold rather than argmax, "winning class" stops being meaningful:
  /// a clip at pReal 0.55 is rejected, and reporting that as "55% confident
  /// spoof" would be backwards.
  double _confidence = 0.0;

  // ── API second-layer state — disabled for now, kept for later ────────────
  // bool _isCallingApi = false;
  // bool _isFinalFailure = false;
  // static const String _apiUrl = 'http://168.144.41.182:8000/api/infer';

  bool _isCollecting = false;
  int _sensorRotation = 0;
  Timer? _restartTimer;

  /// Minimum softmax probability of the "real" class required to pass a clip.
  /// Raising this trades false accepts (spoofs getting through) for false
  /// rejects (real users sent round the retry loop).
  static const double _liveThreshold = 0.8;

  static const List<double> _mean = [0.485, 0.456, 0.406];
  static const List<double> _std  = [0.229, 0.224, 0.225];

  // Animations
  /// Drives the sweep band travelling down the preview.
  late final AnimationController _sweepCtrl;

  /// Drives the indeterminate arc while the model runs.
  late final AnimationController _spinCtrl;

  /// Rotation of the tick wave around the ring. Linear and always running.
  late final AnimationController _tickPhaseCtrl;

  /// Envelope for the tick band: forward while a clip is being captured,
  /// reversed when it stops, so the ticks never appear or vanish abruptly.
  late final AnimationController _tickAmpCtrl;
  late final Animation<double> _tickAmp;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    _initAll();
  }

  void _initAnimations() {
    _sweepCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600))
      ..repeat();
    _spinCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1100))
      ..repeat();

    // One rotation of the wave per 1.8s — a breathing rate, not a strobe.
    _tickPhaseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1800))
      ..repeat();

    _tickAmpCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 320));
    // Same curve in both directions: the band leaves the way it arrived.
    _tickAmp = CurvedAnimation(
      parent: _tickAmpCtrl,
      curve: Motion.enter,
      reverseCurve: Motion.enter,
    );
  }

  /// Single place that flips collection on and off, so the tick envelope can
  /// never drift out of sync with the capture state.
  void _setCollecting(bool collecting) {
    _isCollecting = collecting;
    if (!mounted) return;
    if (collecting) {
      _tickAmpCtrl.forward();
    } else {
      _tickAmpCtrl.reverse();
    }
  }

  Future<void> _initAll() async {
    await Future.wait([_loadModel(), _initCamera()]);
    if (mounted && _modelLoaded && _cameraReady) {
      _startInference();
    }
  }

  /// Picks up the process-wide module. Usually already warm from app start, so
  /// this returns on the first frame; if not, it awaits the same in-flight load
  /// rather than starting a second one.
  Future<void> _loadModel() async {
    final module = await LivenessModel.instance.load();
    if (!mounted) return;
    setState(() {
      _module = module;
      _modelLoaded = module != null;
    });
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) return;
      final cam = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      // Frames are pulled straight off the preview stream, so we want raw
      // planes rather than JPEGs — no disk round-trip, no re-decode.
      _camera = CameraController(cam, ResolutionPreset.medium,
          enableAudio: false, imageFormatGroup: ImageFormatGroup.yuv420);
      await _camera!.initialize();

      // Degrees the sensor image must be rotated clockwise to sit upright.
      // The app is locked to portraitUp, so this is the whole correction.
      _sensorRotation = ((cam.sensorOrientation % 360) + 360) % 360;

      await _camera!.startImageStream(_onCameraFrame);
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

  void _startInference() => _beginClip();

  /// Arms collection. Frames then arrive from the camera stream until the clip
  /// is full, which keeps the 24 frames genuinely consecutive — the clip spans
  /// well under a second, close to how the model was trained.
  void _beginClip() {
    if (_isNavigating || !mounted) return;
    setState(() {
      _framesCollected = 0;
      _windowStart = DateTime.now();
      _hasResult = false;
    });
    _setCollecting(true);
  }

  void _onCameraFrame(CameraImage image) {
    if (!_isCollecting || _isNavigating || !mounted) return;
    if (_framesCollected >= _clipFrames) return;

    try {
      _convertFrameInto(image, _framesCollected);
    } catch (e) {
      debugPrint('Frame convert error: $e');
      return;
    }

    final int next = _framesCollected + 1;
    setState(() => _framesCollected = next);

    if (next >= _clipFrames) {
      _setCollecting(false);
      _runClipInference();
    }
  }

  /// Converts one YUV420 camera frame straight into slot [k] of the clip
  /// buffer. Centre-crop, rotation, downscale, YUV→RGB and ImageNet
  /// normalisation are fused into a single pass over the 224² output, so no
  /// intermediate image or list is allocated per frame.
  void _convertFrameInto(CameraImage image, int k) {
    final int w = image.width;
    final int h = image.height;
    final int side = math.min(w, h);
    final int cropX = (w - side) ~/ 2;
    final int cropY = (h - side) ~/ 2;

    final Plane yP = image.planes[0];
    final Plane uP = image.planes[1];
    final Plane vP = image.planes[2];
    final Uint8List yB = yP.bytes;
    final Uint8List uB = uP.bytes;
    final Uint8List vB = vP.bytes;

    final int yRow  = yP.bytesPerRow;
    final int yPix  = yP.bytesPerPixel ?? 1;
    final int uvRow = uP.bytesPerRow;
    final int uvPix = uP.bytesPerPixel ?? 1;

    // Rotation as an affine map on the cropped square: the source coordinate
    // is a1*x + b1*y + c1 (and a2/b2/c2 for y), with coefficients in {-1,0,1}.
    final int last = side - 1;
    int a1, b1, c1, a2, b2, c2;
    switch (_sensorRotation) {
      case 90:
        a1 = 0;  b1 = 1;  c1 = 0;     a2 = -1; b2 = 0;  c2 = last;
        break;
      case 180:
        a1 = -1; b1 = 0;  c1 = last;  a2 = 0;  b2 = -1; c2 = last;
        break;
      case 270:
        a1 = 0;  b1 = -1; c1 = last;  a2 = 1;  b2 = 0;  c2 = 0;
        break;
      default:
        a1 = 1;  b1 = 0;  c1 = 0;     a2 = 0;  b2 = 1;  c2 = 0;
    }

    final int base = k * _floatsPerFrame;
    final double mR = _mean[0], mG = _mean[1], mB = _mean[2];
    final double sR = _std[0],  sG = _std[1],  sB = _std[2];

    for (int oy = 0; oy < _inputSize; oy++) {
      final int by0 = (oy * side) ~/ _inputSize;
      final int by1 = math.max(((oy + 1) * side) ~/ _inputSize, by0 + 1) - 1;

      for (int ox = 0; ox < _inputSize; ox++) {
        final int bx0 = (ox * side) ~/ _inputSize;
        final int bx1 = math.max(((ox + 1) * side) ~/ _inputSize, bx0 + 1) - 1;

        // Map both corners of the output block through the rotation, then take
        // the axis-aligned span they bound in source space.
        final int pxA = a1 * bx0 + b1 * by0 + c1;
        final int pxB = a1 * bx1 + b1 * by1 + c1;
        final int pyA = a2 * bx0 + b2 * by0 + c2;
        final int pyB = a2 * bx1 + b2 * by1 + c2;
        final int sx0 = cropX + (pxA < pxB ? pxA : pxB);
        final int sx1 = cropX + (pxA < pxB ? pxB : pxA);
        final int sy0 = cropY + (pyA < pyB ? pyA : pyB);
        final int sy1 = cropY + (pyA < pyB ? pyB : pyA);

        // Box-average luma over the block; chroma is already subsampled, so a
        // single sample at the block centre carries enough colour.
        int ySum = 0, n = 0;
        for (int sy = sy0; sy <= sy1; sy++) {
          final int rowOff = sy * yRow;
          for (int sx = sx0; sx <= sx1; sx++) {
            ySum += yB[rowOff + sx * yPix];
            n++;
          }
        }
        final double yVal = ySum / n;

        final int cx = (sx0 + sx1) >> 1;
        final int cy = (sy0 + sy1) >> 1;
        final int uvIdx = (cy >> 1) * uvRow + (cx >> 1) * uvPix;
        final double u = uB[uvIdx] - 128.0;
        final double v = vB[uvIdx] - 128.0;

        // Full-range BT.601 — the same conversion a JPEG decode would apply,
        // so values match what the training pipeline saw.
        double r = yVal + 1.370705 * v;
        double g = yVal - 0.337633 * u - 0.698001 * v;
        double b = yVal + 1.732446 * u;
        r = r < 0 ? 0 : (r > 255 ? 255 : r);
        g = g < 0 ? 0 : (g > 255 ? 255 : g);
        b = b < 0 ? 0 : (b > 255 ? 255 : b);

        final int p = oy * _inputSize + ox;
        _clipBuffer[base + p] = (r / 255.0 - mR) / sR;
        _clipBuffer[base + _pixelsPerFrame + p] = (g / 255.0 - mG) / sG;
        _clipBuffer[base + 2 * _pixelsPerFrame + p] = (b / 255.0 - mB) / sB;
      }
    }
  }

  // ── Inference ─────────────────────────────────────────────────────────────

  Future<void> _runClipInference() async {
    if (_module == null || _isNavigating || !mounted) return;

    _isProcessing = true;
    final double clipSecs = _elapsedSeconds;
    final Stopwatch sw = Stopwatch()..start();
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

      debugPrint('clip ${clipSecs.toStringAsFixed(2)}s · '
          'infer ${sw.elapsedMilliseconds}ms · '
          'real=${realLogit.toStringAsFixed(3)} '
          'fake=${fakeLogit.toStringAsFixed(3)} '
          'pFake=${pFake.toStringAsFixed(4)}');

      // A clip must be confidently real, not merely more-real-than-fake:
      // plain argmax (pFake < 0.5) passed anything over a coin flip.
      final bool isReal = pFake < (1 - _liveThreshold);

      setState(() {
        _hasResult  = true;
        _isSpoof    = !isReal;
        _confidence = 1 - pFake;
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
      _beginClip();
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
    setState(() => _isNavigating = true);
    _restartTimer?.cancel();

    // Let the ring settle on the verified state before the screen changes.
    Future.delayed(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, a, __) => SuccessPage(confidence: _confidence),
          transitionsBuilder: (_, a, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: a, curve: Motion.enter),
            child: child,
          ),
          transitionDuration: Motion.slow,
        ),
      );
    });
  }

  @override
  void dispose() {
    _sweepCtrl.dispose();
    _spinCtrl.dispose();
    _tickPhaseCtrl.dispose();
    _tickAmpCtrl.dispose();
    _restartTimer?.cancel();
    // Stop feeding the converter before the controller goes away.
    _isCollecting = false;
    _camera?.dispose();
    // The module is process-wide and deliberately outlives this screen — see
    // LivenessModel. Destroying it here is what made every visit reload it.
    super.dispose();
  }


  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            Expanded(
              child: LayoutBuilder(
                builder: (context, c) => Center(
                  child: _buildViewfinder(
                    math.min(c.maxWidth - Space.gutter * 2, c.maxHeight),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Space.gutter, 0, Space.gutter, Space.lg),
              child: _buildStatus(),
            ),
          ],
        ),
      ),
    );
  }

  // ── Header ────────────────────────────────────────────────────────────────
  Widget _buildHeader() {
    final t = Theme.of(context).textTheme;
    final p = context.palette;

    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.md, Space.sm, Space.gutter, 0),
      child: Row(
        children: [
          Semantics(
            button: true,
            label: 'Back',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.of(context).maybePop(),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Icon(Icons.arrow_back,
                    size: 20, color: p.textSecondary),
              ),
            ),
          ),
          const SizedBox(width: Space.xs),
          Text('VERIFICATION', style: t.labelSmall),
        ],
      ),
    );
  }

  // ── Viewfinder ────────────────────────────────────────────────────────────
  // One circle. A hairline track, a single arc that fills as the clip is
  // collected, and the preview inside it — nothing else on the canvas.
  Widget _buildViewfinder(double maxD) {
    // Shrink to fit short screens rather than overflowing; the ring keeps its
    // proportions and the preview keeps its inset.
    final double boxD = maxD.clamp(200.0, 320.0);
    // Outer band reserved for the capture ticks; the ring track sits inside it.
    const double tickBand = 18.0;
    final double cameraD = boxD - tickBand * 2 - 28;

    final p = context.palette;
    final still = reducedMotion(context);

    final Color arcColor = _isNavigating
        ? p.success
        : (_hasResult && _isSpoof ? p.danger : p.ink);

    // Verdict states close the ring; collection fills it frame by frame.
    final double progress =
        (_isNavigating || (_hasResult && _isSpoof)) ? 1.0 : _clipProgress;

    return SizedBox(
      width: boxD,
      height: boxD,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Ticks repaint every frame while capturing, so they get their own
          // layer and drive themselves off the controllers — no widget rebuild.
          RepaintBoundary(
            child: CustomPaint(
              size: Size(boxD, boxD),
              painter: CaptureTicksPainter(
                phase: _tickPhaseCtrl,
                amplitude: _tickAmp,
                color: p.ink,
                inset: tickBand,
                still: still,
              ),
            ),
          ),
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _spinCtrl,
              builder: (context, _) => CustomPaint(
                size: Size(boxD, boxD),
                painter: ScanRingPainter(
                  progress: progress,
                  spin: still ? 0 : _spinCtrl.value,
                  indeterminate: _isProcessing && !_isNavigating,
                  trackColor: p.border,
                  arcColor: arcColor,
                  inset: tickBand,
                ),
              ),
            ),
          ),
          ClipOval(
            child: SizedBox(
              width: cameraD,
              height: cameraD,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _buildCameraContent(),
                  if (_isCollecting && !still)
                    AnimatedBuilder(
                      animation: _sweepCtrl,
                      builder: (context, _) => CustomPaint(
                        painter: ScanSweepPainter(
                          progress: _sweepCtrl.value,
                          // Always light: this sits on live video, not on the
                          // page surface, so it must not follow the theme.
                          color: Colors.white,
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
  }

  double get _clipProgress => _framesCollected / _clipFrames;

  Widget _buildCameraContent() {
    final p = context.palette;

    if (!_cameraReady || _camera == null) {
      return Container(
        color: p.surfaceMuted,
        alignment: Alignment.center,
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 1.5,
            color: p.textGhost,
          ),
        ),
      );
    }

    // previewSize is reported landscape-first, so the axes are swapped here
    // before BoxCover crops it into the circle — otherwise the face stretches.
    final preview = _camera!.value.previewSize;
    final bool mirror = _camera!.description.lensDirection ==
        CameraLensDirection.front;

    Widget view = FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: preview?.height ?? 1,
        height: preview?.width ?? 1,
        child: CameraPreview(_camera!),
      ),
    );

    if (mirror) {
      view = Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()..scaleByDouble(-1.0, 1.0, 1.0, 1.0),
        child: view,
      );
    }
    return view;
  }

  // ── Status ────────────────────────────────────────────────────────────────
  // Replaces the old bordered card and 24-bar strip. A rule, a state line and
  // two lines of copy: the ring already carries the progress.
  Widget _buildStatus() {
    final t = Theme.of(context).textTheme;
    final p = context.palette;

    final ({String state, String title, String detail, Color tone, bool working}) s =
        _statusFor(p);

    final bool showCounter =
        !_isNavigating && !_isProcessing && !(_hasResult && _isSpoof) &&
            _modelLoaded && _cameraReady;

    return FadeRise(
      delay: const Duration(milliseconds: 120),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: p.borderSubtle),
          const SizedBox(height: Space.md),
          Row(
            children: [
              AnimatedContainer(
                duration: Motion.base,
                width: 6,
                height: 6,
                decoration: BoxDecoration(color: s.tone, shape: BoxShape.circle),
              ),
              const SizedBox(width: Space.sm),
              SwapLabel(
                text: s.state,
                style: t.labelSmall?.copyWith(color: s.tone),
                // Breathe only where nothing else on screen is moving:
                // capturing already has the tick band, verdicts are settled.
                breathing: s.working,
              ),
              const Spacer(),
              AnimatedOpacity(
                opacity: showCounter ? 1 : 0,
                duration: Motion.fast,
                child: Text(
                  '${_framesCollected.toString().padLeft(2, '0')} / $_clipFrames',
                  style: t.labelSmall?.copyWith(
                    color: p.textGhost,
                    fontFeatures: AppTheme.tabular,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.md),
          AnimatedSwitcher(
            duration: Motion.base,
            switchInCurve: Motion.enter,
            layoutBuilder: (current, previous) => Stack(
              alignment: Alignment.centerLeft,
              children: [...previous, if (current != null) current],
            ),
            child: Column(
              key: ValueKey(s.title),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.title, style: t.titleMedium),
                const SizedBox(height: 4),
                Text(
                  s.detail,
                  style: t.bodyMedium?.copyWith(color: p.textTertiary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  ({String state, String title, String detail, Color tone, bool working}) _statusFor(
      AppPalette p) {
    if (_isNavigating) {
      return (
        state: 'VERIFIED',
        title: 'Live face confirmed',
        detail: 'Taking you through…',
        tone: p.success,
        working: false,
      );
    }
    if (!_modelLoaded || !_cameraReady) {
      return (
        state: 'PREPARING',
        title: 'Starting the camera',
        detail: 'Loading the on-device model',
        tone: p.textTertiary,
        working: true,
      );
    }
    if (_hasResult && _isSpoof) {
      return (
        state: 'NOT CONFIRMED',
        title: 'That didn’t read as a live face',
        detail: 'Liveness ${(_confidence * 100).toStringAsFixed(0)}%'
            ' · needs ${(_liveThreshold * 100).toStringAsFixed(0)}%'
            ' · trying again',
        tone: p.danger,
        working: false,
      );
    }
    if (_isProcessing) {
      return (
        state: 'ANALYSING',
        title: 'Checking the clip',
        detail: 'All $_clipFrames frames, together, on this device',
        tone: p.textSecondary,
        working: true,
      );
    }
    if (_framesCollected == 0) {
      return (
        state: 'READY',
        title: 'Centre your face',
        detail: 'Fill the circle and look straight ahead',
        tone: p.textSecondary,
        working: false,
      );
    }
    return (
      state: 'CAPTURING',
      title: 'Hold steady',
      detail: 'Move a little — ${_elapsedSeconds.toStringAsFixed(1)}s recorded',
      tone: p.ink,
      working: false,
    );
  }
}
