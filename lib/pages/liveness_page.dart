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
import '../services/challenge_settings.dart';
import '../services/deepfake_api.dart';
import '../services/face_challenge.dart';
import '../services/liveness_model.dart';
import '../theme/app_theme.dart';
import '../widgets/animated_label.dart';
import '../widgets/fade_rise.dart';
import '../services/stage_report.dart';
import 'success_page.dart';
import 'verification_failed_page.dart';

/// Side of the square JPEG posted to stage 3.
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

/// Stage 3's answer for one clip, or why there isn't one.
///
/// The server call runs alongside stage 2 and is sometimes never awaited (a
/// stage-2 fake settles the clip on its own), so the future must never throw:
/// an unawaited failing future is an unhandled error. Failures travel as data.
class _ServerResult {
  final Prediction? prediction;
  final ApiFailure? failure;
  final int elapsedMs;

  const _ServerResult.ok(Prediction p, this.elapsedMs)
      : prediction = p,
        failure = null;

  const _ServerResult.failed(ApiFailure f, this.elapsedMs)
      : prediction = null,
        failure = f;

  @override
  String toString() => prediction != null
      ? '$prediction · ${elapsedMs}ms round trip'
      : 'failed: ${failure!.message} · ${elapsedMs}ms';
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

  // ── Stage 2 contract (mnetv2-anti-spoof-baseline/convert_to_ptl.py) ──────
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

  // ── The decision rule: both must say real ────────────────────────────────
  // Stages 2 and 3 run in parallel on the same clip, and either one can veto:
  //
  //   stage 2 fake                    ->  FAKE  (server not waited for)
  //   stage 2 real, stage 3 FAKE      ->  FAKE
  //   stage 2 real, stage 3 REAL      ->  REAL
  //   stage 2 real, stage 3 no answer ->  not checked, retry
  //
  // Stage 2 says real when the clip's *average* P(real) clears
  // [_liveThreshold]. Individual frames may dip below it — a blink or a bit of
  // motion blur shouldn't sink an honest clip — and how many did is reported
  // on the result screen.

  /// The mean P(real) across the clip's frames must reach this for stage 2 to
  /// call the clip real. Below it, stage 2 says fake.
  static const double _liveThreshold = 0.80;

  // Inference state
  bool _hasResult = false;
  bool _isSpoof = false;

  // ── Stage 3 state ────────────────────────────────────────────────────────

  /// Stage 2 has said real and the screen is waiting on the server's half.
  bool _isEscalating = false;

  // ── Result state ─────────────────────────────────────────────────────────

  /// Layer 1's receipt row: passed, or skipped by the toggle. Null only while
  /// the challenges are still running.
  StageReport? _layer1;

  /// What the status line says in the beat between a failed verdict and the
  /// failure screen opening.
  ({String state, String title, String detail})? _ending;

  /// Set once a result screen has been scheduled; see [_finish].
  bool _finishScheduled = false;

  /// This screen's route, captured where dependency lookups belong
  /// ([didChangeDependencies]) so [_finish]'s delayed callback can check it
  /// without subscribing to anything from outside a build.
  ModalRoute<dynamic>? _route;

  /// Completed by the next camera frame when stage 3 needs an image.
  Completer<Uint8List>? _rawFrameRequest;

  // ── Challenge stage state (ML Kit) ───────────────────────────────────────

  /// Null when the toggle is off, in which case the pipeline is the two
  /// passive stages and the camera goes straight to clip collection.
  FaceChallengeStage? _challenge;

  /// True while the challenges are running and nothing else may touch frames.
  bool _inChallenge = false;

  /// Redraws the shared countdown once a second; the detector's own ticks are
  /// too irregular to drive a clock off.
  Timer? _budgetTicker;

  /// Set briefly when a prompt is satisfied, so the UI can acknowledge it
  /// before the next prompt replaces the line.
  Challenge? _justPassed;
  Timer? _passedTimer;

  /// Why the current prompt is not progressing: no face, or more than one.
  String? _framingNote;

  bool _isCollecting = false;
  int _sensorRotation = 0;

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
    if (!mounted || !_modelLoaded || !_cameraReady) return;

    // The toggle is read once, here. Flipping it mid-check would change what
    // the screen is doing underneath the user.
    final bool challenges = ChallengeSettings.instance.enabled;
    debugPrint('check started · challenge layer '
        '${challenges ? "ON" : "OFF (going straight to layers 2 + 3)"}');
    if (challenges) {
      _beginChallenges();
    } else {
      _layer1 = const StageReport(
        layer: 1,
        name: StageReport.layer1Name,
        outcome: StageOutcome.skipped,
        detail: 'Turned off on the landing screen',
      );
      _startInference();
    }
  }

  // ── Stage 1 of three: the ML Kit challenges ──────────────────────────────

  void _beginChallenges() {
    final stage = FaceChallengeStage()..start();
    setState(() {
      _challenge = stage;
      _inChallenge = true;
      _framingNote = null;
      _justPassed = null;
    });

    // One attempt, one shared 30s clock — so the countdown is the whole of the
    // failure condition and has to keep ticking even if ML Kit sees nothing.
    _budgetTicker?.cancel();
    _budgetTicker = Timer.periodic(const Duration(milliseconds: 250), (_) {
      if (!mounted || !_inChallenge) return;
      if (stage.isExpired) {
        _onChallengesFailed();
      } else {
        setState(() {});
      }
    });
  }

  void _onChallengeFrame(CameraImage image) {
    final stage = _challenge;
    if (stage == null || stage.isBusy) return;

    // Fire and forget: detection is slower than the camera, and the busy flag
    // above is what keeps frames from queueing up behind it.
    unawaited(stage.processFrame(image, _sensorRotation).then((tick) {
      if (!mounted || !_inChallenge) return;
      switch (tick) {
        case ChallengeTick.noFace:
          setState(() => _framingNote = 'No face in frame');
        case ChallengeTick.crowded:
          setState(() => _framingNote = 'More than one face in frame');
        case ChallengeTick.waiting:
          if (_framingNote != null) setState(() => _framingNote = null);
        case ChallengeTick.advanced:
          _acknowledge(stage);
        case ChallengeTick.complete:
          _acknowledge(stage);
          _onChallengesPassed();
        case ChallengeTick.expired:
          _onChallengesFailed();
      }
    }));
  }

  /// Holds the completed prompt on screen for a beat. Without it the line
  /// swaps the instant the user succeeds and it reads as if nothing happened.
  void _acknowledge(FaceChallengeStage stage) {
    final done = stage.completed > 0 ? stage.queue[stage.completed - 1] : null;
    setState(() {
      _justPassed = done;
      _framingNote = null;
    });
    _passedTimer?.cancel();
    _passedTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      setState(() => _justPassed = null);
    });
  }

  void _onChallengesPassed() {
    if (!_inChallenge) return;
    _budgetTicker?.cancel();
    final order = _challenge?.queue.map((c) => c.name).join(' → ') ?? '';
    debugPrint('challenges passed: $order');
    _layer1 = StageReport(
      layer: 1,
      name: StageReport.layer1Name,
      outcome: StageOutcome.passed,
      detail: 'All ${_challenge?.total ?? 4} prompts, with '
          '${_challenge?.remaining.inSeconds ?? 0}s to spare',
    );
    setState(() => _inChallenge = false);
    // Straight into the passive stages; the camera never stops.
    _startInference();
  }

  /// The gate closed. One attempt means this is terminal — no retry loop, and
  /// the model stages never run.
  void _onChallengesFailed() {
    if (!_inChallenge || _isNavigating) return;
    _budgetTicker?.cancel();
    _passedTimer?.cancel();

    final stage = _challenge;
    debugPrint('challenges failed on ${stage?.failedOn?.name} '
        '(${stage?.completed}/${stage?.total})');

    setState(() => _inChallenge = false);

    final failedOn = stage?.failedOn;
    _finish(VerificationFailedPage(
      headline: 'Verification failed',
      reason: failedOn == null
          ? 'The challenge check ran out of time.'
          : 'The challenge check ran out of time on '
              '“${failedOn.prompt.toLowerCase()}”.',
      reports: [
        StageReport(
          layer: 1,
          name: StageReport.layer1Name,
          outcome: StageOutcome.failed,
          detail: '${stage?.completed ?? 0} of '
              '${stage?.total ?? Challenge.values.length} prompts in 30s',
        ),
        _notReached(2),
        _notReached(3),
      ],
    ), delay: Duration.zero);
  }

  /// Picks up the process-wide stage-2 module. Usually already warm from app
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
      // planes rather than JPEGs — no disk round-trip, no re-decode. Stage 3's
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

  /// Arms collection for the check's one clip. Called once per check — every
  /// outcome ends on a result screen, so there is no second clip.
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
    if (_isNavigating || !mounted) return;

    // The challenges own the camera until they are done. Nothing downstream
    // sees a frame before the gate opens.
    if (_inChallenge) {
      _onChallengeFrame(image);
      return;
    }

    // Stage 3 asked for an image; this is the first frame since. Serve it and
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
      _runStage2();
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
  /// bytes: what stage 3 gets, before JPEG. No normalisation — the server does
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

  // ── Stages 2 and 3, in parallel ───────────────────────────────────────────

  /// Scores the clip on device and, at the same time, asks the server about a
  /// frame of it. The clip is real only if both say real.
  ///
  /// The server request goes out first, before the 24 forward passes, so its
  /// round trip overlaps the on-device work instead of following it. A
  /// stage-2 fake settles the clip without waiting for the server at all — the
  /// request still finishes in the background and is logged, but it can no
  /// longer change anything.
  Future<void> _runStage2() async {
    if (_module == null || _isNavigating || !mounted) return;

    // Started first so the frame request is registered while the camera is
    // still streaming. Never throws — see [_ServerResult].
    final Future<_ServerResult> server = _askServer();

    setState(() => _isProcessing = true);
    final double clipSecs = _elapsedSeconds;
    final Stopwatch sw = Stopwatch()..start();

    try {
      double minP = 1.0, maxP = 0.0, sumP = 0.0;
      int below = 0;

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
        if (pReal < _liveThreshold) below++;
        sumP += pReal;
      }

      final double meanP = sumP / _clipFrames;
      final bool mobileReal = meanP >= _liveThreshold;

      debugPrint('stage2 ${clipSecs.toStringAsFixed(2)}s clip · '
          '${sw.elapsedMilliseconds}ms for $_clipFrames frames · '
          'pReal min=${minP.toStringAsFixed(3)} '
          'mean=${meanP.toStringAsFixed(3)} '
          'max=${maxP.toStringAsFixed(3)} · '
          '$below/$_clipFrames below threshold · '
          '${mobileReal ? "REAL" : "FAKE"}');

      if (!mounted) return;
      setState(() => _isProcessing = false);

      String pct(double v) => '${(v * 100).toStringAsFixed(0)}%';
      final String needed = pct(_liveThreshold);
      // The same evidence on a pass or a fail: the average that decided it,
      // and exactly how many frames fell short on their own.
      final String layer2Detail =
          'Average ${pct(meanP)} live · needs $needed\n'
          '$below of $_clipFrames frames below $needed · '
          'lowest ${pct(minP)}';

      if (!mobileReal) {
        // Layer 2 said fake. The server can't overturn that, so the result is
        // settled now. Its answer is still shown when it lands — as evidence
        // layer 3 works, marked as not having counted.
        final layer2 = StageReport(
          layer: 2,
          name: StageReport.layer2Name,
          outcome: StageOutcome.failed,
          detail: layer2Detail,
        );
        final Future<StageReport> layer3 = server.then((r) {
          debugPrint('stage3 (after stage-2 veto) $r');
          return _layer3From(r, informational: r.prediction != null);
        });
        _finishFailed(
          state: 'VERIFICATION FAILED',
          headline: 'Verification failed',
          reason: 'The on-device model averaged ${pct(meanP)} live across '
              '$_clipFrames frames — below the $needed it needs.',
          reports: [
            _layer1Report,
            layer2,
            const StageReport(
              layer: 3,
              name: StageReport.layer3Name,
              outcome: StageOutcome.pending,
              detail: 'Doesn’t change the result — layer 2 already said no',
            ),
          ],
          pendingLayer3: layer3,
        );
        return;
      }

      final layer2 = StageReport(
        layer: 2,
        name: StageReport.layer2Name,
        outcome: StageOutcome.passed,
        detail: layer2Detail,
      );

      // Layer 2 says real. Now the server's half decides.
      setState(() => _isEscalating = true);
      final _ServerResult r = await server;
      if (!mounted || _isNavigating) return;
      debugPrint('stage3 $r');

      final StageReport layer3 = _layer3From(r);
      final Prediction? p = r.prediction;

      if (p == null) {
        // No verdict is not a spoof verdict, so say "couldn't complete" rather
        // than "failed". But both layers must agree, so it can't pass either.
        _finishFailed(
          state: 'NOT COMPLETED',
          headline: 'Couldn’t complete',
          reason: 'The on-device model passed, but the deepfake ensemble '
              'didn’t answer. Both have to agree, so this can’t count as '
              'verified.',
          reports: [_layer1Report, layer2, layer3],
        );
        return;
      }

      if (!p.isReal) {
        _finishFailed(
          state: 'VERIFICATION FAILED',
          headline: 'Verification failed',
          reason: 'The on-device model passed, but the deepfake ensemble '
              'didn’t read a live face.',
          reports: [_layer1Report, layer2, layer3],
        );
        return;
      }

      setState(() {
        _isEscalating = false;
        _hasResult = true;
        _isSpoof = false;
      });
      _finish(SuccessPage(reports: [_layer1Report, layer2, layer3]));
    } catch (e) {
      debugPrint('Stage 2 error: $e');
      if (!mounted) return;
      setState(() {
        _isProcessing = false;
        _isEscalating = false;
      });
      _finishFailed(
        state: 'NOT COMPLETED',
        headline: 'Couldn’t complete',
        reason: 'The on-device model hit an error before it could decide.',
        reports: [
          _layer1Report,
          StageReport(
            layer: 2,
            name: StageReport.layer2Name,
            outcome: StageOutcome.noAnswer,
            detail: '$e',
          ),
          _notReached(3),
        ],
      );
    } finally {
      if (mounted && _isProcessing) setState(() => _isProcessing = false);
    }
  }

  // ── Stage 3: the deepfake ensemble, over the network ──────────────────────

  /// One frame of the clip to the ensemble.
  ///
  /// Touches no widget state, so it is safe to leave running after the screen
  /// has moved on — which happens whenever stage 2 vetoes. Its first real
  /// statement registers the frame request synchronously, before the caller
  /// reaches its own first `await`.
  Future<_ServerResult> _askServer() async {
    final sw = Stopwatch()..start();
    if (!BackendConfig.instance.isConfigured) {
      return const _ServerResult.failed(
          ApiFailure(0, 'No backend URL is set'), 0);
    }
    try {
      final Uint8List rgb = await _requestRawFrame();
      final Uint8List jpeg = await compute(_encodeUploadJpeg, rgb);
      final Prediction p = await DeepfakeApi.predict(jpeg);
      return _ServerResult.ok(p, sw.elapsedMilliseconds);
    } on ApiFailure catch (f) {
      return _ServerResult.failed(f, sw.elapsedMilliseconds);
    } catch (e) {
      return _ServerResult.failed(
          ApiFailure(0, 'Second opinion unavailable: $e'),
          sw.elapsedMilliseconds);
    }
  }

  /// Asks the camera stream for one frame, converted but not yet encoded.
  Future<Uint8List> _requestRawFrame() {
    final c = Completer<Uint8List>();
    _rawFrameRequest = c;
    return c.future.timeout(
      const Duration(seconds: 4),
      onTimeout: () {
        // Only clear the slot if it is still ours: an abandoned request timing
        // out (after a stage-2 veto) must not cancel the next clip's.
        if (identical(_rawFrameRequest, c)) _rawFrameRequest = null;
        throw const ApiFailure(0, 'The camera did not deliver a frame');
      },
    );
  }

  // ── Ending the check ──────────────────────────────────────────────────────
  // One attempt per check. Every outcome ends on a result screen; nothing
  // loops back into another clip.

  /// Layer 1's row, whether it passed or was switched off.
  StageReport get _layer1Report =>
      _layer1 ??
      const StageReport(
        layer: 1,
        name: StageReport.layer1Name,
        outcome: StageOutcome.skipped,
      );

  StageReport _notReached(int layer) => StageReport(
        layer: layer,
        name: layer == 2 ? StageReport.layer2Name : StageReport.layer3Name,
        outcome: StageOutcome.notReached,
        detail: 'An earlier layer ended the check',
      );

  /// Turns a server result into layer 3's receipt row. Touches no widget
  /// state, so it is safe to run after this screen has gone.
  StageReport _layer3From(_ServerResult r, {bool informational = false}) {
    final Prediction? p = r.prediction;
    if (p == null) {
      final f = r.failure!;
      return StageReport(
        layer: 3,
        name: StageReport.layer3Name,
        outcome: StageOutcome.noAnswer,
        detail: !BackendConfig.instance.isConfigured
            ? 'No server URL set'
            : f.isUnreachable
                ? 'Server unreachable — ${f.message}'
                : (f.isAuth ? 'Server rejected the API key' : f.message),
      );
    }
    return StageReport(
      layer: 3,
      name: StageReport.layer3Name,
      outcome: p.isReal ? StageOutcome.passed : StageOutcome.failed,
      detail: '${(p.probReal * 100).toStringAsFixed(1)}% live · '
          'routed to ${p.routedTo}',
      informational: informational,
    );
  }

  /// Closes the ring in red, holds it for a beat, then opens the failure
  /// screen. [state] is what the status line says during that beat.
  void _finishFailed({
    required String state,
    required String headline,
    required String reason,
    required List<StageReport> reports,
    Future<StageReport>? pendingLayer3,
  }) {
    if (!mounted || _isNavigating) return;
    setState(() {
      _isEscalating = false;
      _hasResult = true;
      _isSpoof = true;
      _ending = (state: state, title: headline, detail: reason);
    });
    _finish(VerificationFailedPage(
      headline: headline,
      reason: reason,
      reports: reports,
      pendingLayer3: pendingLayer3,
    ));
  }

  /// Replaces this screen with a result screen. The default delay lets the
  /// ring settle on its final colour before the screen changes.
  ///
  /// Guarded twice, because a route change here that goes wrong corrupts the
  /// navigator rather than failing cleanly:
  /// - it runs at most once per screen, whatever calls it;
  /// - by the time the delay ends, this screen must still be the top route. A
  ///   route that is popping is still `mounted`, and `pushReplacement` from it
  ///   would replace whatever is on top instead — the landing page.
  void _finish(Widget page,
      {Duration delay = const Duration(milliseconds: 850)}) {
    if (!mounted || _finishScheduled) return;
    _finishScheduled = true;
    setState(() => _isNavigating = true);

    void go() {
      if (!mounted || _route?.isCurrent != true) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          pageBuilder: (_, a, __) => page,
          transitionsBuilder: (_, a, __, child) => FadeTransition(
            opacity: CurvedAnimation(parent: a, curve: Motion.enter),
            child: child,
          ),
          transitionDuration: Motion.slow,
        ),
      );
    }

    if (delay == Duration.zero) {
      go();
    } else {
      Future.delayed(delay, go);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
  }

  @override
  void dispose() {
    _sweepCtrl.dispose();
    _spinCtrl.dispose();
    _tickPhaseCtrl.dispose();
    _tickAmpCtrl.dispose();
    _budgetTicker?.cancel();
    _passedTimer?.cancel();
    // Stop feeding the converter before the controller goes away.
    _isCollecting = false;
    _inChallenge = false;
    // An in-flight stage-3 capture would otherwise hang until its timeout.
    _rawFrameRequest = null;
    // The detector holds a native ML Kit handle, so unlike the TorchScript
    // modules it does have to be closed.
    unawaited(_challenge?.dispose());
    _camera?.dispose();
    // The modules are process-wide and deliberately outlive this screen — see
    // LivenessModel. Destroying them here is what made every visit reload them.
    super.dispose();
  }


  // ─── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Once a result is decided the screen is committed to replacing itself;
    // backing out in the 850ms beat would race that replacement.
    return PopScope(
      canPop: !_isNavigating,
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
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
              // maybePop respects the PopScope above, so this is inert once a
              // result is decided.
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

    // Verdict states close the ring; collection fills it frame by frame, and
    // during the challenges it counts prompts instead.
    final double progress = (_isNavigating || (_hasResult && _isSpoof))
        ? 1.0
        : (_inChallenge ? (_challenge?.progress ?? 0) : _clipProgress);

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

    // During the challenges the same slot carries the shared clock — it is
    // the only thing standing between the user and a failed check.
    final String counter = _inChallenge
        ? '${_challenge?.remaining.inSeconds ?? 0}s left'
        : '${_framesCollected.toString().padLeft(2, '0')} / $_clipFrames';

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
                opacity: showCounter || _inChallenge ? 1 : 0,
                duration: Motion.fast,
                child: Text(
                  counter,
                  style: t.labelSmall?.copyWith(
                    // The clock goes red for the last five seconds. It is the
                    // only warning the user gets before a one-attempt fail.
                    color: _inChallenge &&
                            (_challenge?.remaining.inSeconds ?? 99) <= 5
                        ? p.danger
                        : p.textGhost,
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
    // Checked before `_isNavigating`: a failure also navigates, and must not
    // read as VERIFIED during the beat before its screen opens.
    final ending = _ending;
    if (ending != null) {
      return (
        state: ending.state,
        title: ending.title,
        detail: ending.detail,
        tone: p.danger,
        working: false,
      );
    }
    if (_isNavigating) {
      return (
        state: 'VERIFIED',
        title: 'Live face confirmed',
        detail: 'On device and by the ensemble · taking you through…',
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
    if (_inChallenge) return _challengeStatus(p);
    if (_isEscalating) {
      return (
        state: 'CONFIRMING',
        title: 'On-device check passed',
        detail: 'Waiting for the deepfake ensemble to agree',
        tone: p.textSecondary,
        working: true,
      );
    }
    if (_isProcessing) {
      return (
        state: 'ANALYSING',
        title: 'Checking the clip',
        detail: 'All $_clipFrames frames on this device · '
            'the ensemble checks one in parallel',
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

  /// The challenge stage speaks in instructions rather than status: the user
  /// has one attempt and a shared clock, so the prompt is the whole screen.
  ({String state, String title, String detail, Color tone, bool working})
      _challengeStatus(AppPalette p) {
    final stage = _challenge;
    if (stage == null || stage.isComplete) {
      return (
        state: 'CHALLENGE',
        title: 'Getting ready',
        detail: 'Centre your face in the circle',
        tone: p.textSecondary,
        working: true,
      );
    }

    // An acknowledgement outranks the next prompt for a beat, so completing
    // one reads as progress rather than as the screen jumping. The final
    // prompt never lands here: finishing the sequence leaves the challenge
    // phase in the same tick, and the scan's own status takes over.
    if (_justPassed != null) {
      return (
        state: 'CHALLENGE ${stage.completed} / ${stage.total}',
        title: 'Good',
        detail: 'Next: ${stage.current.prompt.toLowerCase()}',
        tone: p.success,
        working: false,
      );
    }

    if (_framingNote != null) {
      return (
        state: 'CHALLENGE ${stage.completed + 1} / ${stage.total}',
        title: stage.current.prompt,
        detail: '$_framingNote — the clock is still running',
        tone: p.danger,
        working: true,
      );
    }

    return (
      state: 'CHALLENGE ${stage.completed + 1} / ${stage.total}',
      title: stage.current.prompt,
      detail: stage.current.hint,
      tone: p.ink,
      working: true,
    );
  }
}
