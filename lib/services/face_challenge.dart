import 'dart:math' as math;
import 'dart:ui' show Size;

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

/// One thing the user is asked to do on camera.
///
/// ML Kit has no "liveness" endpoint. What it gives is a head pose and two
/// classification scores per face; the test is what we build on top, and the
/// test is the point: a still photo has no yaw, a printed mask does not blink,
/// and a replayed video cannot answer prompts it did not know were coming.
enum Challenge {
  turnLeft('Turn your head left', 'Slowly — keep your eyes on the screen'),
  turnRight('Turn your head right', 'Slowly — keep your eyes on the screen'),
  blink('Blink', 'One clear blink, both eyes'),
  smile('Smile', 'Wide enough to read');

  const Challenge(this.prompt, this.hint);

  final String prompt;
  final String hint;
}

/// What one processed frame did to the sequence.
enum ChallengeTick {
  /// No usable face. Nothing counted and nothing failed — the clock still runs.
  noFace,

  /// More than one face. Deliberately not progress: a challenge satisfied with
  /// a second person in shot proves nothing about who is being verified.
  crowded,

  /// A face, but the current challenge is not met yet.
  waiting,

  /// The current challenge just completed and another one follows.
  advanced,

  /// Every challenge is done. Hand over to stage 3.
  complete,

  /// The shared budget ran out. One attempt, so this is terminal.
  expired,
}

/// Stage 1 of three: the ML Kit challenge sequence.
///
/// Holds the detector, the randomised queue and the shared clock. The caller
/// feeds it camera frames and reads back a [ChallengeTick]; it owns no UI and
/// no camera.
class FaceChallengeStage {
  FaceChallengeStage({math.Random? random, DateTime Function()? clock})
      : _random = random ?? math.Random(),
        _now = clock ?? DateTime.now;

  /// One clock for the whole sequence rather than a timer per challenge, so a
  /// user who turns their head quickly banks that time for the blink.
  static const Duration budget = Duration(seconds: 30);

  // ── Thresholds ───────────────────────────────────────────────────────────

  /// Degrees of yaw that count as a deliberate turn. Below roughly 20° is
  /// within the range of someone sitting still and shifting slightly.
  static const double _yawDegrees = 25.0;

  /// Eyes must be seen this open before a blink can be registered…
  static const double _eyesOpen = 0.60;

  /// …and then this shut. Requiring the transition is what separates a blink
  /// from a photograph of someone with their eyes closed.
  static const double _eyesShut = 0.25;

  static const double _smiling = 0.70;

  /// ML Kit reads yaw off the raw sensor image, which for a front camera is
  /// unmirrored — so a user turning to *their* left appears to turn toward the
  /// right of the image, and `headEulerAngleY` goes positive. That is the
  /// assumption [_yawOf] encodes. It is the one thing here that cannot be
  /// checked without a device in hand: if the two turn prompts come out
  /// swapped on real hardware, flip this and nothing else.
  static const bool invertYaw = false;

  final math.Random _random;

  /// Injectable so the one-attempt expiry rule can be tested without waiting
  /// thirty seconds. Production always passes `DateTime.now`.
  final DateTime Function() _now;

  late final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      // Required for smilingProbability and the eye-open scores; without it
      // those fields come back null and three of the four challenges break.
      enableClassification: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  List<Challenge> _queue = const [];
  int _index = 0;
  bool _eyesWereOpen = false;
  bool _busy = false;
  DateTime? _startedAt;
  Challenge? _failedOn;

  // ── State the UI reads ───────────────────────────────────────────────────

  List<Challenge> get queue => List.unmodifiable(_queue);
  int get completed => _index;
  int get total => _queue.length;
  bool get isComplete => _queue.isNotEmpty && _index >= _queue.length;
  Challenge get current => _queue[_index];

  /// The challenge the clock ran out on, once it has.
  Challenge? get failedOn => _failedOn;

  /// True while a frame is still inside ML Kit. Detection is slower than the
  /// camera, so the caller skips frames instead of queueing them.
  bool get isBusy => _busy;

  Duration get remaining {
    if (_startedAt == null) return budget;
    final left = budget - _now().difference(_startedAt!);
    return left.isNegative ? Duration.zero : left;
  }

  bool get isExpired => _startedAt != null && remaining == Duration.zero;

  double get progress => total == 0 ? 0 : _index / total;

  /// Shuffles a fresh sequence and starts the clock.
  ///
  /// The order is randomised per run because that is where most of the
  /// anti-replay value sits: a video recorded once cannot know whether this
  /// run will ask for a blink first or a smile.
  void start() {
    _queue = List<Challenge>.of(Challenge.values)..shuffle(_random);
    _index = 0;
    _eyesWereOpen = false;
    _failedOn = null;
    _startedAt = _now();
  }

  /// Feeds one camera frame through ML Kit and advances the sequence.
  ///
  /// [sensorRotation] is the camera's `sensorOrientation`; the app is locked
  /// to portrait, so that is the whole correction ML Kit needs.
  Future<ChallengeTick> processFrame(
      CameraImage image, int sensorRotation) async {
    if (isComplete) return ChallengeTick.complete;
    if (isExpired) {
      _failedOn ??= _queue.isEmpty ? null : current;
      return ChallengeTick.expired;
    }
    if (_busy) return ChallengeTick.waiting;

    _busy = true;
    try {
      final input = _toInputImage(image, sensorRotation);
      if (input == null) return ChallengeTick.waiting;
      return submitFaces(await _detector.processImage(input));
    } catch (e) {
      debugPrint('ML Kit error: $e');
      return ChallengeTick.waiting;
    } finally {
      _busy = false;
    }
  }

  /// The decision half of [processFrame], split out from the detection half so
  /// the rules can be exercised with synthetic faces and no camera. This is
  /// where the sequence actually advances.
  @visibleForTesting
  ChallengeTick submitFaces(List<Face> faces) {
    if (isComplete) return ChallengeTick.complete;

    // The clock may have run out while ML Kit was working on the frame.
    if (isExpired) {
      _failedOn ??= current;
      return ChallengeTick.expired;
    }
    if (faces.isEmpty) return ChallengeTick.noFace;
    if (faces.length > 1) return ChallengeTick.crowded;

    final Face face = faces.first;
    final bool satisfied = _satisfies(current, face);

    // Updated *after* the check, so one frame can never supply both halves of
    // the open-then-shut transition a blink needs.
    final double? l = face.leftEyeOpenProbability;
    final double? r = face.rightEyeOpenProbability;
    if (l != null && r != null && l >= _eyesOpen && r >= _eyesOpen) {
      _eyesWereOpen = true;
    }

    if (!satisfied) return ChallengeTick.waiting;

    _index++;
    // A later blink in the same run needs its own open-then-shut pair.
    _eyesWereOpen = false;
    return isComplete ? ChallengeTick.complete : ChallengeTick.advanced;
  }

  bool _satisfies(Challenge c, Face f) {
    switch (c) {
      case Challenge.turnLeft:
        final yaw = _yawOf(f);
        return yaw != null && yaw >= _yawDegrees;
      case Challenge.turnRight:
        final yaw = _yawOf(f);
        return yaw != null && yaw <= -_yawDegrees;
      case Challenge.blink:
        final l = f.leftEyeOpenProbability;
        final r = f.rightEyeOpenProbability;
        if (l == null || r == null) return false;
        return _eyesWereOpen && l <= _eyesShut && r <= _eyesShut;
      case Challenge.smile:
        final s = f.smilingProbability;
        return s != null && s >= _smiling;
    }
  }

  double? _yawOf(Face f) {
    final y = f.headEulerAngleY;
    if (y == null) return null;
    return invertYaw ? -y : y;
  }

  // ── Frame conversion ─────────────────────────────────────────────────────

  InputImage? _toInputImage(CameraImage image, int sensorRotation) {
    final rotation = InputImageRotationValue.fromRawValue(sensorRotation);
    if (rotation == null || image.planes.length < 3) return null;

    return InputImage.fromBytes(
      bytes: _yuv420ToNv21(image),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: InputImageFormat.nv21,
        // NV21 stores one byte per luma sample with no row padding, so a row
        // is exactly the image width — not the camera plane's bytesPerRow.
        bytesPerRow: image.width,
      ),
    );
  }

  /// Repacks the camera's three-plane YUV420 into the single NV21 buffer ML
  /// Kit wants on Android: the full luma plane, then chroma interleaved V then
  /// U at quarter resolution.
  ///
  /// The camera stays on `yuv420` because the stage-3 tensor path is built
  /// around those planes; converting here costs one pass over a frame and
  /// avoids reconfiguring the controller between stages.
  static Uint8List _yuv420ToNv21(CameraImage image) {
    final int w = image.width;
    final int h = image.height;
    final int uvW = (w + 1) ~/ 2;
    final int uvH = (h + 1) ~/ 2;

    final out = Uint8List(w * h + uvW * uvH * 2);

    final Plane yP = image.planes[0];
    final int yRow = yP.bytesPerRow;
    final int yPix = yP.bytesPerPixel ?? 1;
    int o = 0;

    if (yPix == 1) {
      // The common case: rows are contiguous, so copy them wholesale.
      for (int r = 0; r < h; r++) {
        out.setRange(o, o + w, yP.bytes, r * yRow);
        o += w;
      }
    } else {
      for (int r = 0; r < h; r++) {
        final int row = r * yRow;
        for (int c = 0; c < w; c++) {
          out[o++] = yP.bytes[row + c * yPix];
        }
      }
    }

    final Plane uP = image.planes[1];
    final Plane vP = image.planes[2];
    final int uvPix = uP.bytesPerPixel ?? 1;
    for (int r = 0; r < uvH; r++) {
      final int uRow = r * uP.bytesPerRow;
      final int vRow = r * vP.bytesPerRow;
      for (int c = 0; c < uvW; c++) {
        // NV21 is V first, then U.
        out[o++] = vP.bytes[vRow + c * uvPix];
        out[o++] = uP.bytes[uRow + c * uvPix];
      }
    }
    return out;
  }

  Future<void> dispose() async {
    try {
      await _detector.close();
    } catch (e) {
      debugPrint('ML Kit close error: $e');
    }
  }
}
