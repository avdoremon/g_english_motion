import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/calibrator.dart';
import 'package:g_english_motion/input/jump_detector.dart';
import 'package:g_english_motion/input/pose_types.dart';

import '../helpers/synthetic_poses.dart';

const cal = Calibration(
  torsoHeight: 0.3,
  centerX: 0.5,
  baselineHipY: 0.6,
  baselineShoulderY: 0.3,
);

Duration ms(int v) => Duration(milliseconds: v);
Pose lifted(double lift) => makePose(hipY: 0.6 - lift);

void main() {
  test('lift of 0.04 fires exactly once, even while held above debounce', () {
    final d = JumpDetector(cal);
    expect(d.update(lifted(0), ms(0)), isFalse);
    expect(d.update(lifted(0.04), ms(33)), isTrue);
    expect(d.update(lifted(0.04), ms(66)), isFalse);
    expect(d.update(lifted(0.04), ms(800)), isFalse);
  });

  test('re-jump 300 ms after landing is ignored, 700 ms is accepted', () {
    final d = JumpDetector(cal);
    d.update(lifted(0), ms(0));
    expect(d.update(lifted(0.04), ms(100)), isTrue);
    expect(d.update(lifted(0), ms(300)), isFalse);
    expect(d.update(lifted(0.04), ms(400)), isFalse); // 300 ms after fire
    expect(d.update(lifted(0), ms(450)), isFalse);
    expect(d.update(lifted(0.04), ms(800)), isTrue); // 700 ms after fire
  });

  test('lift of 0.02 does not fire', () {
    final d = JumpDetector(cal);
    d.update(lifted(0), ms(0));
    expect(d.update(lifted(0.02), ms(33)), isFalse);
    expect(d.update(lifted(0.02), ms(66)), isFalse);
  });

  test('suppressUntil blocks jumps in the window', () {
    final d = JumpDetector(cal);
    d.update(lifted(0), ms(0));
    d.suppressUntil(ms(500));
    expect(d.update(lifted(0.04), ms(100)), isFalse);
    expect(d.update(lifted(0.04), ms(400)), isFalse);
    expect(d.update(lifted(0), ms(600)), isFalse);
    expect(d.update(lifted(0.04), ms(700)), isTrue);
  });

  test('missing hips/shoulders never fire', () {
    final d = JumpDetector(cal);
    expect(d.update(const Pose({}), ms(0)), isFalse);
  });

  test('slowly backing away (torso 0.3 -> 0.25 over 5 s) never fires', () {
    final d = JumpDetector(cal);
    var fired = 0;
    for (final f in backingAwaySequence()) {
      if (d.update(f.poses.first, f.timestamp)) fired++;
    }
    expect(fired, 0);
  });

  test('10 synthetic jumps (0.5 s airtime) -> 10 +/- 1 events', () {
    final d = JumpDetector(cal);
    var fired = 0;
    for (final f in jumpSequence(jumps: 10)) {
      if (d.update(f.poses.first, f.timestamp)) fired++;
    }
    expect(fired, inInclusiveRange(9, 11));
  });

  test('standing still with jitter never fires', () {
    final d = JumpDetector(cal);
    var fired = 0;
    for (final f in standingSequence(
      duration: const Duration(seconds: 10),
      noise: 0.004,
    )) {
      if (d.update(f.poses.first, f.timestamp)) fired++;
    }
    expect(fired, 0);
  });

  group('baseline adaptation', () {
    /// 30 fps frames where the whole body is lifted by lift(t) metres.
    List<PoseFrame> levels(double seconds, double Function(double t) lift) =>
        poseSequence(
          duration: Duration(milliseconds: (seconds * 1000).round()),
          posesAt: (t) => [lifted(lift(t.inMicroseconds / 1e6))],
        );

    List<int> run(JumpDetector d, List<PoseFrame> frames) => [
      for (final f in frames)
        if (d.update(f.poses.first, f.timestamp)) f.timestamp.inMilliseconds,
    ];

    test('slow drift beyond the threshold (0.08 over 8 s) never fires, '
        'and a later real jump fires exactly once', () {
      final d = JumpDetector(cal);
      // 1 s rest, 8 s drift up by 0.08 (> 0.036 threshold), 3 s settle.
      double drift(double t) => t < 1 ? 0 : (t < 9 ? 0.01 * (t - 1) : 0.08);
      expect(run(d, levels(12, drift)), isEmpty);
      // Real jump of 0.04 from the new resting level (half-sine, 0.5 s).
      final jump = poseSequence(
        duration: const Duration(seconds: 2),
        start: const Duration(seconds: 12),
        posesAt: (t) {
          final u = (t - const Duration(seconds: 12)).inMilliseconds / 500;
          return [lifted(0.08 + (u < 1 ? 0.04 * math.sin(math.pi * u) : 0))];
        },
      );
      expect(run(d, jump), hasLength(1));
    });

    test('baseline does not adapt during or just after a jump', () {
      final d = JumpDetector(cal);
      // Jump at t=1 s, stay aloft 0.55 s (inside debounce), land, rest 0.7 s,
      // jump again: only fires if the baseline stayed on the ground.
      double lift(double t) {
        if (t >= 1.0 && t < 1.55) return 0.04;
        if (t >= 2.25 && t < 2.8) return 0.04;
        return 0;
      }

      final fired = run(d, levels(3.5, lift));
      expect(fired, hasLength(2));
    });

    test('persistent positive offset (0.05), settle 2 s: later jump fires', () {
      final d = JumpDetector(cal);
      final stepUp = run(d, levels(1, (t) => t < 0.5 ? 0 : 0.05));
      expect(stepUp.length, lessThanOrEqualTo(1)); // the step may fire once
      final settle = poseSequence(
        duration: const Duration(seconds: 3),
        start: const Duration(seconds: 1),
        posesAt: (_) => [lifted(0.05)],
      );
      expect(run(d, settle), isEmpty);
      final jump = poseSequence(
        duration: const Duration(seconds: 1),
        start: const Duration(seconds: 4),
        posesAt: (t) {
          final u = (t - const Duration(seconds: 4)).inMilliseconds / 500;
          return [lifted(0.05 + (u < 1 ? 0.04 * math.sin(math.pi * u) : 0))];
        },
      );
      expect(run(d, jump), hasLength(1));
    });

    test(
      'persistent negative offset (steps away), settle: jump 0.04 fires',
      () {
        final d = JumpDetector(cal);
        expect(run(d, levels(1, (t) => t < 0.5 ? 0 : -0.05)), isEmpty);
        final settle = poseSequence(
          duration: const Duration(seconds: 3),
          start: const Duration(seconds: 1),
          posesAt: (_) => [lifted(-0.05)],
        );
        expect(run(d, settle), isEmpty);
        final jump = poseSequence(
          duration: const Duration(seconds: 1),
          start: const Duration(seconds: 4),
          posesAt: (t) {
            final u = (t - const Duration(seconds: 4)).inMilliseconds / 500;
            return [lifted(-0.05 + (u < 1 ? 0.04 * math.sin(math.pi * u) : 0))];
          },
        );
        expect(run(d, jump), hasLength(1));
      },
    );

    for (final fps in [30, 60]) {
      test('persistent +0.05 offset with +/-0.003 jitter @ $fps fps: later '
          '0.04 jump fires', () {
        final d = JumpDetector(cal);
        var i = 0;
        double jitter() =>
            0.003 * math.sin(i++ * 12.9898) * math.cos(i * 78.233);
        run(
          d,
          poseSequence(
            duration: const Duration(seconds: 1),
            fps: fps,
            posesAt: (t) => [
              lifted((t.inMilliseconds < 500 ? 0 : 0.05) + jitter()),
            ],
          ),
        );
        final settle = poseSequence(
          duration: const Duration(seconds: 3),
          fps: fps,
          start: const Duration(seconds: 1),
          posesAt: (_) => [lifted(0.05 + jitter())],
        );
        expect(run(d, settle), isEmpty);
        final jump = poseSequence(
          duration: const Duration(seconds: 1),
          fps: fps,
          start: const Duration(seconds: 4),
          posesAt: (t) {
            final u = (t - const Duration(seconds: 4)).inMilliseconds / 500;
            return [
              lifted(
                0.05 + jitter() + (u < 1 ? 0.04 * math.sin(math.pi * u) : 0),
              ),
            ];
          },
        );
        expect(run(d, jump), hasLength(1));
      });
    }

    test(
      '0.9 s airtime jumps do not re-baseline mid-air: 3 jumps -> 3 events',
      () {
        final d = JumpDetector(cal);
        final frames = jumpSequence(
          jumps: 3,
          airtime: const Duration(milliseconds: 900),
          noise: 0,
        );
        expect(run(d, frames), hasLength(3));
      },
    );
  });

  group('time-based behaviour at 15 fps (single-pose plugin)', () {
    List<int> run(JumpDetector d, List<PoseFrame> frames) => [
      for (final f in frames)
        if (d.update(f.poses.first, f.timestamp)) f.timestamp.inMilliseconds,
    ];

    /// Lift(t) in seconds -> frames at [fps].
    List<PoseFrame> lifts(
      double seconds,
      double Function(double t) lift, {
      int fps = 15,
      Duration start = Duration.zero,
    }) => poseSequence(
      duration: Duration(milliseconds: (seconds * 1000).round()),
      fps: fps,
      start: start,
      posesAt: (t) => [lifted(lift((t - start).inMicroseconds / 1e6))],
    );

    for (final fps in [15, 30]) {
      test('rise 0.04 in 0.15 s fires exactly once @ $fps fps', () {
        final d = JumpDetector(cal);
        double lift(double t) {
          if (t < 1.5) return 0;
          if (t < 1.65) return 0.04 * (t - 1.5) / 0.15;
          if (t < 2.0) return 0.04;
          return 0;
        }

        expect(run(d, lifts(3.5, lift, fps: fps)), hasLength(1));
      });

      test('slow walk toward the camera (0.02/s for 3 s), then standing, '
          'never fires @ $fps fps', () {
        final d = JumpDetector(cal);
        // 1 s rest, 3 s drift (total 0.06 > threshold 0.036), 4 s standing.
        double drift(double t) => t < 1 ? 0 : (t < 4 ? 0.02 * (t - 1) : 0.06);
        expect(run(d, lifts(8, drift, fps: fps)), isEmpty);
      });

      test('slow walk away (-0.02/s) never fires @ $fps fps', () {
        final d = JumpDetector(cal);
        double drift(double t) => t < 1 ? 0 : (t < 4 ? -0.02 * (t - 1) : -0.06);
        expect(run(d, lifts(8, drift, fps: fps)), isEmpty);
      });

      test('real jump after a slow walk still fires exactly once '
          '@ $fps fps', () {
        final d = JumpDetector(cal);
        double drift(double t) => t < 1 ? 0 : (t < 4 ? 0.02 * (t - 1) : 0.06);
        expect(run(d, lifts(7, drift, fps: fps)), isEmpty);
        final jump = lifts(
          2,
          (t) => 0.06 + (t < 0.15 ? 0.04 * t / 0.15 : (t < 0.5 ? 0.04 : 0)),
          fps: fps,
          start: const Duration(seconds: 7),
        );
        expect(run(d, jump), hasLength(1));
      });
    }

    test('10 jumps of rise 0.04 (0.5 s airtime) @ 15 fps -> 10 +/- 1', () {
      final d = JumpDetector(cal);
      final frames = jumpSequence(jumps: 10, rise: 0.04, fps: 15, noise: 0);
      expect(run(d, frames).length, inInclusiveRange(9, 11));
    });

    test('standing with jitter @ 15 fps never fires', () {
      final d = JumpDetector(cal);
      final frames = standingSequence(
        duration: const Duration(seconds: 10),
        fps: 15,
        noise: 0.004,
      );
      expect(run(d, frames), isEmpty);
    });

    test('a persistent +0.05 step @ 15 fps re-baselines and a later 0.04 '
        'jump fires', () {
      final d = JumpDetector(cal);
      run(d, lifts(1, (t) => t < 0.5 ? 0 : 0.05));
      expect(
        run(d, lifts(3, (_) => 0.05, start: const Duration(seconds: 1))),
        isEmpty,
      );
      final jump = lifts(
        1,
        (t) => 0.05 + (t < 0.15 ? 0.04 * t / 0.15 : 0.04),
        start: const Duration(seconds: 4),
      );
      expect(run(d, jump), hasLength(1));
    });
  });
}
