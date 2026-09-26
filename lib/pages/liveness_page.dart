import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter_pytorch_lite/flutter_pytorch_lite.dart';
import 'package:image/image.dart' as img;
import '../painters/scan_ring_painter.dart';
import '../services/backend_config.dart';
import '../services/deepfake_api.dart';
import '../services/liveness_model.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_label.dart';
import '../widgets/fade_rise.dart';
import 'success_page.dart';

/// Side of the square JPEG posted to stage 2.
///
/// The server resizes whatever it gets to 342² and scores the central 299²
/// window, so sending 384² means that resize is a downscale rather than an
/// upscale — the ensemble never sees interpolated detail we invented.
const int _uploadSize = 384;

/// Runs on a background isolate: interleaved RGB bytes to JPEG. Encoding
/// 384² inline costs enough to drop frames on the preview behind it.
Uint8List _encodeUploadJpeg(Uint8List rgb) {
  final frame = img.Image.fromBytes(
    width: _uploadSize,
    height: _uploadSize,
    bytes: rgb.buffer,
    numChannels: 3,
  );
  return img.encodeJpg(frame, quality: 92);
}

/// What stage 1 concluded about a clip.
enum _Stage1 {
  /// Every frame was confidently real. Decided on device, no network.
  live,

  /// Every frame was confidently a spoof. Also decided on device.
  spoof,

  /// The frames disagreed, or some of them landed in the middle. This is the
  /// only outcome that costs a round-trip.
  uncertain,
}

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

  // ── Stage 1 contract (mnetv2-anti-spoof-baseline/convert_to_ptl.py) ──────
  // Input : float32 [1, 3, 224, 224], layout N-C-H-W, RGB, ImageNet-normalised
  // Output: float32 [1, 1] — already through a sigmoid, and it is P(real)
  static const int _inputSize      = 224;
  static const int _pixelsPerFrame = _inputSize * _inputSize;   //  50,176
  static const int _floatsPerFrame = 3 * _pixelsPerFrame;       // 150,528

  /// How many frames one decision is made from. The model is per-frame, so
  /// this is purely the consistency window: the more frames, the harder it is
  /// for a spoof to slip through on one lucky frame.
  static const int _clipFrames = 24;
  static const int _clipFloats = _clipFrames * _floatsPerFrame; // 3,612,672

  /// The clip's input tensor, allocated once and refilled per clip (~13.8 MiB).
  /// Each frame occupies its own [_floatsPerFrame] slice and is scored on its
  /// own; the buffer is one allocation, not one tensor.
  final Float32List _clipBuffer = Float32List(_clipFloats);
  int _framesCollected = 0;
  DateTime? _windowStart;

  // ── The escalation rule ──────────────────────────────────────────────────
  // A clip is settled on device only when the frames are *unanimous* and past
  // the margin. One frame in the middle, or two frames pointing opposite ways,
  // and the decision is not ours to make — it goes to stage 2.
  //
  //   min(pReal) >= 0.80  ->  live    (decided here)
  //   max(pReal) <= 0.20  ->  spoof   (decided here)
  //   otherwise           ->  stage 2 (deepfake ensemble)

  /// Every frame must clear this for a local pass.
  static const double _liveMargin = 0.80;

  /// Every frame must sit below this for a local reject.
  static const double _spoofMargin = 0.20;

  // Inference state
  bool _hasResult = false;
  bool _isSpoof = false;

  /// Probability that the face is real, on the scale the verdict was made on:
  /// the clip's mean P(real) for a local decision, the ensemble's `1 -
  /// prob_fake` for a server one. Not "confidence in the winning class" —
  /// under a threshold that reading is backwards, because a clip at 0.55 is
  /// rejected and reporting it as "55% spoof" would invert the number.
  double _confidence = 0.0;

  /// Per-frame spread from the last clip, shown so a near miss is legible.
  double _minP = 0, _maxP = 0;

  // ── Stage 2 state ────────────────────────────────────────────────────────
  bool _isEscalating = false;

  /// Set when stage 2 could not be reached. The check is not failed on this —
  /// it retries on device — but the user is told the second opinion is missing.
  String? _offlineNote;

  /// The ensemble's router class for the last server verdict, for the status
  /// line. Detail only: the label comes from the score, never from this.
  String? _routedTo;

  /// Completed by the next camera frame when stage 2 needs an image.
  Completer<Uint8List>? _rawFrameRequest;

  bool _isCollecting = false;
  int _sensorRotation = 0;
  Timer? _restartTimer;

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

  /// Picks up the process-wide stage-1 module. Usually already warm from app
  /// start, so this returns on the first frame; if not, it awaits the same
  /// in-flight load rather than starting a second one.
  Future<void> _loadModel() async {
    final module = await LivenessModel.instance.mobilenetV2.load();
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
      // planes rather than JPEGs — no disk round-trip, no re-decode. Stage 2's
      // upload is encoded from the same stream, so the camera is never
      // interrupted mid-check to take a picture.
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
  // Frames are gathered back-to-back (not on a fixed timer) so the window
  // stays short in real time: 24 consecutive frames span well under a second,
  // which is a genuine consistency test rather than a sample of poses.

  void _startInference() => _beginClip();

  void _beginClip() {
    if (_isNavigating || !mounted) return;
    setState(() {
      _framesCollected = 0;
      _windowStart = DateTime.now();
      _hasResult = false;
      _offlineNote = null;
      _routedTo = null;
    });
    _setCollecting(true);
  }

  void _onCameraFrame(CameraImage image) {
    if (_isNavigating || !mounted) return;

    // Stage 2 asked for an image; this is the first frame since. Serve it and
    // fall through — a capture request never costs the clip a frame.
    final pending = _rawFrameRequest;
    if (pending != null) {
      _rawFrameRequest = null;
      try {
        pending.complete(_rgbFrameBytes(image));
      } catch (e) {
        pending.completeError(ApiFailure(0, 'Could not read the camera: $e'));
      }
    }

    if (!_isCollecting) return;
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
      _runStage1();
    }
  }

  // ── Frame geometry ────────────────────────────────────────────────────────

  /// Centre-crop origin, square side, and the affine coefficients that rotate
  /// that square upright. Shared by the tensor path and the upload path so the
  /// ensemble is shown the same framing the local model scored.
  ///
  /// The source coordinate for output `(x, y)` is `a1*x + b1*y + c1` across and
  /// `a2*x + b2*y + c2` down, with every coefficient in `{-1, 0, 1}`.
  ({int cropX, int cropY, int side, int a1, int b1, int c1, int a2, int b2, int c2})
      _geometryFor(int w, int h) {
    final int side = math.min(w, h);
    final int last = side - 1;
    switch (_sensorRotation) {
      case 90:
        return (cropX: (w - side) ~/ 2, cropY: (h - side) ~/ 2, side: side,
            a1: 0, b1: 1, c1: 0, a2: -1, b2: 0, c2: last);
      case 180:
        return (cropX: (w - side) ~/ 2, cropY: (h - side) ~/ 2, side: side,
            a1: -1, b1: 0, c1: last, a2: 0, b2: -1, c2: last);
      case 270:
        return (cropX: (w - side) ~/ 2, cropY: (h - side) ~/ 2, side: side,
            a1: 0, b1: -1, c1: last, a2: 1, b2: 0, c2: 0);
      default:
        return (cropX: (w - side) ~/ 2, cropY: (h - side) ~/ 2, side: side,
            a1: 1, b1: 0, c1: 0, a2: 0, b2: 1, c2: 0);
    }
  }

  /// Converts one YUV420 camera frame straight into slot [k] of the clip
  /// buffer. Centre-crop, rotation, downscale, YUV→RGB and ImageNet
  /// normalisation are fused into a single pass over the 224² output, so no
  /// intermediate image or list is allocated per frame. The upload path below
  /// repeats the loop rather than sharing it through a callback: this one runs
  /// 1.2M times per clip and a per-pixel closure is not free.
  void _convertFrameInto(CameraImage image, int k) {
    final g = _geometryFor(image.width, image.height);

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

    final int base = k * _floatsPerFrame;
    final double mR = _mean[0], mG = _mean[1], mB = _mean[2];
    final double sR = _std[0],  sG = _std[1],  sB = _std[2];

    for (int oy = 0; oy < _inputSize; oy++) {
      final int by0 = (oy * g.side) ~/ _inputSize;
      final int by1 = math.max(((oy + 1) * g.side) ~/ _inputSize, by0 + 1) - 1;

      for (int ox = 0; ox < _inputSize; ox++) {
        final int bx0 = (ox * g.side) ~/ _inputSize;
        final int bx1 = math.max(((ox + 1) * g.side) ~/ _inputSize, bx0 + 1) - 1;

        // Map both corners of the output block through the rotation, then take
        // the axis-aligned span they bound in source space.
        final int pxA = g.a1 * bx0 + g.b1 * by0 + g.c1;
        final int pxB = g.a1 * bx1 + g.b1 * by1 + g.c1;
        final int pyA = g.a2 * bx0 + g.b2 * by0 + g.c2;
        final int pyB = g.a2 * bx1 + g.b2 * by1 + g.c2;
        final int sx0 = g.cropX + (pxA < pxB ? pxA : pxB);
        final int sx1 = g.cropX + (pxA < pxB ? pxB : pxA);
        final int sy0 = g.cropY + (pyA < pyB ? pyA : pyB);
        final int sy1 = g.cropY + (pyA < pyB ? pyB : pyA);

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
        double gg = yVal - 0.337633 * u - 0.698001 * v;
        double b = yVal + 1.732446 * u;
        r  = r  < 0 ? 0 : (r  > 255 ? 255 : r);
        gg = gg < 0 ? 0 : (gg > 255 ? 255 : gg);
        b  = b  < 0 ? 0 : (b  > 255 ? 255 : b);

        final int p = oy * _inputSize + ox;
        _clipBuffer[base + p] = (r / 255.0 - mR) / sR;
        _clipBuffer[base + _pixelsPerFrame + p] = (gg / 255.0 - mG) / sG;
        _clipBuffer[base + 2 * _pixelsPerFrame + p] = (b / 255.0 - mB) / sB;
      }
    }
  }

  /// The same crop and rotation, at [_uploadSize] and as plain interleaved RGB
  /// bytes: what stage 2 gets, before JPEG. No normalisation — the server does
  /// its own preprocessing and wants ordinary pixels. Not mirrored, matching
  /// what the local model scored; the preview is mirrored for the user only.
  Uint8List _rgbFrameBytes(CameraImage image) {
    final g = _geometryFor(image.width, image.height);

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

    final out = Uint8List(_uploadSize * _uploadSize * 3);

    for (int oy = 0; oy < _uploadSize; oy++) {
      final int by0 = (oy * g.side) ~/ _uploadSize;
      final int by1 = math.max(((oy + 1) * g.side) ~/ _uploadSize, by0 + 1) - 1;

      for (int ox = 0; ox < _uploadSize; ox++) {
        final int bx0 = (ox * g.side) ~/ _uploadSize;
        final int bx1 =
            math.max(((ox + 1) * g.side) ~/ _uploadSize, bx0 + 1) - 1;

        final int pxA = g.a1 * bx0 + g.b1 * by0 + g.c1;
        final int pxB = g.a1 * bx1 + g.b1 * by1 + g.c1;
        final int pyA = g.a2 * bx0 + g.b2 * by0 + g.c2;
        final int pyB = g.a2 * bx1 + g.b2 * by1 + g.c2;
        final int sx0 = g.cropX + (pxA < pxB ? pxA : pxB);
        final int sx1 = g.cropX + (pxA < pxB ? pxB : pxA);
        final int sy0 = g.cropY + (pyA < pyB ? pyA : pyB);
        final int sy1 = g.cropY + (pyA < pyB ? pyB : pyA);

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

        double r = yVal + 1.370705 * v;
        double gg = yVal - 0.337633 * u - 0.698001 * v;
        double b = yVal + 1.732446 * u;
        r  = r  < 0 ? 0 : (r  > 255 ? 255 : r);
        gg = gg < 0 ? 0 : (gg > 255 ? 255 : gg);
        b  = b  < 0 ? 0 : (b  > 255 ? 255 : b);

        final int o = (oy * _uploadSize + ox) * 3;
        out[o]     = r.toInt();
        out[o + 1] = gg.toInt();
        out[o + 2] = b.toInt();
      }
    }
    return out;
  }

  // ── Stage 1: MobileNetV2, per frame, on device ────────────────────────────

  Future<void> _runStage1() async {
    if (_module == null || _isNavigating || !mounted) return;

    setState(() => _isProcessing = true);
    final double clipSecs = _elapsedSeconds;
    final Stopwatch sw = Stopwatch()..start();

    try {
      double minP = 1.0, maxP = 0.0, sumP = 0.0;

      for (int k = 0; k < _clipFrames; k++) {
        if (!mounted || _isNavigating) return;

        // A view over the frame's slice — the buffer is not copied per frame.
        final Tensor input = Tensor.fromBlobFloat32(
          Float32List.sublistView(
              _clipBuffer, k * _floatsPerFrame, (k + 1) * _floatsPerFrame),
          Int64List.fromList([1, 3, _inputSize, _inputSize]),
        );

        final IValue output = await _module!.forward([IValue.from(input)]);
        final Float32List out = output.toTensor().dataAsFloat32List;
        if (out.isEmpty) return;

        // The sigmoid is inside the traced graph, so this is already P(real)
        // in [0, 1]. Nothing to soft-max and nothing to invert.
        final double pReal = out[0];
        if (pReal < minP) minP = pReal;
        if (pReal > maxP) maxP = pReal;
        sumP += pReal;
      }

      final double meanP = sumP / _clipFrames;

      final _Stage1 verdict = minP >= _liveMargin
          ? _Stage1.live
          : (maxP <= _spoofMargin ? _Stage1.spoof : _Stage1.uncertain);

      debugPrint('stage1 ${clipSecs.toStringAsFixed(2)}s clip · '
          '${sw.elapsedMilliseconds}ms for $_clipFrames frames · '
          'pReal min=${minP.toStringAsFixed(3)} '
          'mean=${meanP.toStringAsFixed(3)} '
          'max=${maxP.toStringAsFixed(3)} · ${verdict.name}');

      if (!mounted) return;
      setState(() {
        _minP = minP;
        _maxP = maxP;
        _isProcessing = false;
      });

      switch (verdict) {
        case _Stage1.live:
          setState(() {
            _hasResult = true;
            _isSpoof = false;
            _confidence = meanP;
          });
          _onRealDetected();
        case _Stage1.spoof:
          setState(() {
            _hasResult = true;
            _isSpoof = true;
            _confidence = meanP;
          });
          _onSpoofDetected();
        case _Stage1.uncertain:
          await _runStage2(fallbackConfidence: meanP);
      }
    } catch (e) {
      debugPrint('Stage 1 error: $e');
      if (mounted) setState(() => _isProcessing = false);
      _retryShortly();
    } finally {
      if (mounted && _isProcessing) setState(() => _isProcessing = false);
    }
  }

  // ── Stage 2: the deepfake ensemble, over the network ──────────────────────

  /// Sends one frame to the server and lets its verdict stand. Unreachable is
  /// deliberately **not** a failed check: the user is told the second opinion
  /// is missing and the loop starts a fresh clip, rather than being blocked by
  /// a Kaggle notebook that happens to be asleep.
  Future<void> _runStage2({required double fallbackConfidence}) async {
    if (_isNavigating || !mounted) return;

    if (!BackendConfig.instance.isConfigured) {
      debugPrint('Stage 2 skipped: no backend URL configured');
      _showOffline('No second-opinion server is set up', fallbackConfidence);
      return;
    }

    setState(() {
      _isEscalating = true;
      _offlineNote = null;
    });

    try {
      final Uint8List rgb = await _requestRawFrame();
      final Uint8List jpeg = await compute(_encodeUploadJpeg, rgb);
      final Prediction p = await DeepfakeApi.predict(jpeg);
      if (!mounted || _isNavigating) return;

      debugPrint('stage2 $p');

      setState(() {
        _isEscalating = false;
        _hasResult = true;
        _isSpoof = !p.isReal;
        // The server's own scale, so the number on screen matches the verdict
        // that produced it.
        _confidence = p.probReal;
        _routedTo = p.routedTo;
      });

      if (p.isReal) {
        _onRealDetected();
      } else {
        _onSpoofDetected();
      }
    } on ApiFailure catch (f) {
      debugPrint('Stage 2 failed: $f');
      _showOffline(
        f.isUnreachable
            ? 'Second-opinion server unreachable'
            : (f.isAuth ? 'Server rejected the API key' : f.message),
        fallbackConfidence,
      );
    } catch (e) {
      debugPrint('Stage 2 error: $e');
      _showOffline('Second opinion unavailable', fallbackConfidence);
    }
  }

  /// Asks the camera stream for one frame, converted but not yet encoded.
  Future<Uint8List> _requestRawFrame() {
    final c = Completer<Uint8List>();
    _rawFrameRequest = c;
    return c.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () {
        _rawFrameRequest = null;
        throw const ApiFailure(0, 'The camera did not deliver a frame');
      },
    );
  }

  void _showOffline(String note, double fallbackConfidence) {
    if (!mounted || _isNavigating) return;
    setState(() {
      _isEscalating = false;
      _hasResult = true;
      // Nothing confirmed a live face, so the ring must not read as a pass —
      // but the copy says "couldn't check", not "you failed".
      _isSpoof = true;
      _confidence = fallbackConfidence;
      _offlineNote = note;
    });
    _retryShortly();
  }

  /// A verdict shows, then a fresh clip starts — the user is never stuck on a
  /// dead end, whichever stage produced it.
  void _onSpoofDetected() => _retryShortly();

  void _retryShortly() {
    _restartTimer?.cancel();
    _restartTimer = Timer(const Duration(milliseconds: 3500), () {
      if (!mounted || _isNavigating) return;
      _beginClip();
    });
  }

  void _onRealDetected() {
    if (_isNavigating) return;
    setState(() => _isNavigating = true);
    _restartTimer?.cancel();

    // Let the ring settle on the verified state before the screen changes.
    Future.delayed(const Duration(milliseconds: 850), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, a, __) =>
              SuccessPage(confidence: _confidence, routedTo: _routedTo),
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
    // An in-flight stage-2 capture would otherwise hang until its timeout.
    _rawFrameRequest = null;
    _camera?.dispose();
    // The modules are process-wide and deliberately outlive this screen — see
    // LivenessModel. Destroying them here is what made every visit reload them.
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
                  // The network round-trip is the longest wait in the app, so
                  // it drives the same indeterminate arc the local model does.
                  indeterminate:
                      (_isProcessing || _isEscalating) && !_isNavigating,
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
  // A rule, a state line and two lines of copy: the ring already carries the
  // progress, so the text carries only which stage is speaking.
  Widget _buildStatus() {
    final t = Theme.of(context).textTheme;
    final p = context.palette;

    final ({String state, String title, String detail, Color tone, bool working}) s =
        _statusFor(p);

    final bool showCounter = !_isNavigating &&
        !_isProcessing &&
        !_isEscalating &&
        !(_hasResult && _isSpoof) &&
        _modelLoaded &&
        _cameraReady;

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
              key: ValueKey(s.title + s.detail),
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
        detail: _routedTo == null
            ? 'Taking you through…'
            : 'Confirmed by the ensemble · taking you through…',
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
    if (_isEscalating) {
      return (
        state: 'SECOND OPINION',
        title: 'Frames didn’t agree',
        detail: 'Asking the deepfake ensemble — this needs the network',
        tone: p.textSecondary,
        working: true,
      );
    }
    if (_offlineNote != null) {
      return (
        state: 'NOT CHECKED',
        title: 'Couldn’t get a second opinion',
        detail: '$_offlineNote · trying again',
        tone: p.danger,
        working: false,
      );
    }
    if (_hasResult && _isSpoof) {
      return (
        state: 'NOT CONFIRMED',
        title: 'That didn’t read as a live face',
        detail: _routedTo == null
            // Local reject: every frame agreed, so the range is the evidence.
            ? 'On-device ${(_minP * 100).toStringAsFixed(0)}'
                '–${(_maxP * 100).toStringAsFixed(0)}% live · trying again'
            : 'Ensemble ${(_confidence * 100).toStringAsFixed(0)}% live'
                ' · routed to $_routedTo · trying again',
        tone: p.danger,
        working: false,
      );
    }
    if (_isProcessing) {
      return (
        state: 'ANALYSING',
        title: 'Checking the clip',
        detail: 'All $_clipFrames frames, one by one, on this device',
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
