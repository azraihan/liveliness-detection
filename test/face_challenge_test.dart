import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'package:face_liveness_demo/services/face_challenge.dart';

/// A synthetic ML Kit face. Only the four signals the challenges read are
/// meaningful; the geometry is filler.
Face _face({
  double? yaw,
  double? eyes,
  double? smile,
}) {
  return Face(
    boundingBox: const Rect.fromLTWH(0, 0, 100, 100),
    landmarks: const {},
    contours: const {},
    headEulerAngleY: yaw,
    leftEyeOpenProbability: eyes,
    rightEyeOpenProbability: eyes,
    smilingProbability: smile,
  );
}

/// A face that satisfies whichever challenge is asked for.
Face _satisfying(Challenge c) {
  switch (c) {
    case Challenge.turnLeft:
      return _face(yaw: 40, eyes: 0.9, smile: 0.0);
    case Challenge.turnRight:
      return _face(yaw: -40, eyes: 0.9, smile: 0.0);
    case Challenge.blink:
      return _face(yaw: 0, eyes: 0.05, smile: 0.0);
    case Challenge.smile:
      return _face(yaw: 0, eyes: 0.9, smile: 0.95);
  }
}

/// Eyes wide, head straight, not smiling — satisfies nothing.
final Face _neutral = _face(yaw: 0, eyes: 0.95, smile: 0.02);

/// A clock the test advances by hand.
class _FakeClock {
  DateTime _t = DateTime(2026, 1, 1);
  DateTime call() => _t;
  void advance(Duration d) => _t = _t.add(d);
}

void main() {
  group('challenge sequence', () {
    test('randomises the order but always asks all four', () {
      final orders = <String>{};
      for (var seed = 0; seed < 40; seed++) {
        final stage = FaceChallengeStage(random: math.Random(seed))..start();
        expect(stage.total, Challenge.values.length);
        expect(stage.queue.toSet(), Challenge.values.toSet());
        orders.add(stage.queue.map((c) => c.name).join(','));
      }
      // A fixed order would collapse to a single string.
      expect(orders.length, greaterThan(1));
    });

    test('completing every prompt in order finishes the stage', () {
      final stage = FaceChallengeStage(random: math.Random(7))..start();

      for (var i = 0; i < stage.total; i++) {
        final want = stage.current;

        // A neutral face never advances it.
        expect(stage.submitFaces([_neutral]), ChallengeTick.waiting);

        // The blink rule needs eyes seen open first; the neutral frame above
        // supplies that, which is exactly how it works on camera.
        final tick = stage.submitFaces([_satisfying(want)]);
        expect(
          tick,
          i == stage.total - 1 ? ChallengeTick.complete : ChallengeTick.advanced,
        );
      }

      expect(stage.isComplete, isTrue);
      expect(stage.completed, Challenge.values.length);
      expect(stage.progress, 1.0);
    });
  });

  group('blink needs a transition, not just shut eyes', () {
    /// Drives the stage to whichever prompt we want to examine.
    FaceChallengeStage stageAt(Challenge target) {
      for (var seed = 0; seed < 200; seed++) {
        final s = FaceChallengeStage(random: math.Random(seed))..start();
        if (s.queue.first == target) return s;
      }
      fail('no seed produced $target first');
    }

    test('shut eyes alone do not count — a photo would pass that', () {
      final stage = stageAt(Challenge.blink);
      // Never seen open: this is a still of someone with their eyes closed.
      expect(stage.submitFaces([_face(yaw: 0, eyes: 0.02, smile: 0.0)]),
          ChallengeTick.waiting);
      expect(stage.completed, 0);
    });

    test('open then shut counts', () {
      final stage = stageAt(Challenge.blink);
      expect(stage.submitFaces([_face(yaw: 0, eyes: 0.95, smile: 0.0)]),
          ChallengeTick.waiting);
      expect(stage.submitFaces([_face(yaw: 0, eyes: 0.02, smile: 0.0)]),
          ChallengeTick.advanced);
      expect(stage.completed, 1);
    });

    test('a face with null classification scores never advances', () {
      final stage = stageAt(Challenge.blink);
      expect(stage.submitFaces([_face()]), ChallengeTick.waiting);
      expect(stage.completed, 0);
    });
  });

  group('framing', () {
    test('no face is neither progress nor failure', () {
      final stage = FaceChallengeStage(random: math.Random(3))..start();
      expect(stage.submitFaces([]), ChallengeTick.noFace);
      expect(stage.completed, 0);
      expect(stage.failedOn, isNull);
    });

    test('a second face in shot blocks progress', () {
      final stage = FaceChallengeStage(random: math.Random(3))..start();
      final good = _satisfying(stage.current);
      expect(stage.submitFaces([good, _neutral]), ChallengeTick.crowded);
      expect(stage.completed, 0);
    });
  });

  group('one attempt, one shared budget', () {
    test('the clock expires the run and records where it stopped', () {
      final clock = _FakeClock();
      final stage =
          FaceChallengeStage(random: math.Random(11), clock: clock.call)
            ..start();

      clock.advance(FaceChallengeStage.budget - const Duration(seconds: 1));
      expect(stage.isExpired, isFalse);
      final stillRunning = stage.current;

      clock.advance(const Duration(seconds: 2));
      expect(stage.isExpired, isTrue);
      expect(stage.remaining, Duration.zero);

      // Even a perfect frame cannot rescue it — that is the one-attempt rule.
      expect(stage.submitFaces([_satisfying(stillRunning)]),
          ChallengeTick.expired);
      expect(stage.failedOn, stillRunning);
      expect(stage.isComplete, isFalse);
    });

    test('time banked on an easy prompt is available for a later one', () {
      final clock = _FakeClock();
      final stage =
          FaceChallengeStage(random: math.Random(5), clock: clock.call)
            ..start();

      // Answer the first two almost instantly. The neutral frame before each
      // one is what a real camera would deliver anyway, and it is what arms
      // the blink rule's open-then-shut transition.
      void answer() {
        stage.submitFaces([_neutral]);
        stage.submitFaces([_satisfying(stage.current)]);
      }

      answer();
      clock.advance(const Duration(seconds: 1));
      answer();
      expect(stage.completed, 2);

      // Over 20s on the third would blow a 10s-per-challenge rule, but the
      // budget is shared, so it is still live.
      clock.advance(const Duration(seconds: 20));
      expect(stage.isExpired, isFalse);
      stage.submitFaces([_neutral]);
      expect(stage.submitFaces([_satisfying(stage.current)]),
          ChallengeTick.advanced);
    });
  });
}
