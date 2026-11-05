import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/calibrator.dart';
import 'package:g_english_motion/input/pose_types.dart';

import '../helpers/synthetic_poses.dart';

CalibrationProgress feed(Calibrator c, List<PoseFrame> frames) {
  late CalibrationProgress last;
  for (final f in frames) {
    last = c.add(f);
  }
  return last;
}

void main() {
  test('60 still frames at 30 fps produce a result', () {
    final p = feed(
      Calibrator(),
      standingSequence(duration: const Duration(seconds: 2), noise: 0.002),
    );
    expect(p.progress, 1.0);
    expect(p.issue, isNull);
    expect(p.result, isNotNull);
    expect(p.result!.torsoHeight, closeTo(0.3, 0.005));
    expect(p.result!.centerX, closeTo(0.5, 0.01));
    expect(p.selectedPoseIndex, 0);
  });

  test('progress grows while holding', () {
    final c = Calibrator();
    final frames = standingSequence(duration: const Duration(seconds: 2));
    late CalibrationProgress mid;
    for (final f in frames.take(30)) {
      mid = c.add(f);
    }
    expect(mid.progress, inInclusiveRange(0.4, 0.6));
    expect(mid.result, isNull);
    expect(mid.issue, isNull);
  });

  test('strong oscillation gives notStill and no result', () {
    final frames = poseSequence(
      duration: const Duration(seconds: 2),
      posesAt: (t) => [
        makePose(hipY: 0.6 + (t.inMilliseconds ~/ 100 % 2 == 0 ? 0.05 : -0.05)),
      ],
    );
    final p = feed(Calibrator(), frames);
    expect(p.issue, CalibrationIssue.notStill);
    expect(p.result, isNull);
  });

  test('picks the still pose closest to center', () {
    final frames = poseSequence(
      duration: const Duration(seconds: 2),
      posesAt: (_) => [makePose(hipX: 0.8), makePose(hipX: 0.5)],
    );
    final p = feed(Calibrator(), frames);
    expect(p.result, isNotNull);
    expect(p.selectedPoseIndex, 1);
    expect(p.result!.centerX, closeTo(0.5, 0.01));
  });

  test('a moving centered pose is skipped for a still off-center one', () {
    final frames = poseSequence(
      duration: const Duration(seconds: 2),
      posesAt: (t) => [
        makePose(hipX: 0.5, hipY: 0.6 + (t.inMilliseconds ~/ 100 % 2) * 0.05),
        makePose(hipX: 0.65),
      ],
    );
    final p = feed(Calibrator(), frames);
    expect(p.selectedPoseIndex, 1);
    expect(p.result!.centerX, closeTo(0.65, 0.01));
  });

  test('missing knees gives tooClose', () {
    final frames = poseSequence(
      duration: const Duration(seconds: 2),
      posesAt: (_) => [makePose(knees: false)],
    );
    final p = feed(Calibrator(), frames);
    expect(p.issue, CalibrationIssue.tooClose);
    expect(p.result, isNull);
  });

  test('nose too near the top edge gives tooClose', () {
    final frames = poseSequence(
      duration: const Duration(seconds: 2),
      posesAt: (_) => [makePose(noseY: 0.05)],
    );
    expect(feed(Calibrator(), frames).issue, CalibrationIssue.tooClose);
  });

  test('missing nose gives tooClose', () {
    final frames = poseSequence(
      duration: const Duration(seconds: 2),
      posesAt: (_) {
        final p = makePose();
        return [Pose(Map.of(p.joints)..remove(PoseJoint.nose))];
      },
    );
    expect(feed(Calibrator(), frames).issue, CalibrationIssue.tooClose);
  });

  test('no poses gives noPerson', () {
    final frames = poseSequence(
      duration: const Duration(seconds: 1),
      posesAt: (_) => const [],
    );
    final p = feed(Calibrator(), frames);
    expect(p.issue, CalibrationIssue.noPerson);
    expect(p.progress, 0);
  });

  test('person far from the center gives notCentered', () {
    final frames = poseSequence(
      duration: const Duration(seconds: 2),
      posesAt: (_) => [makePose(hipX: 0.85)],
    );
    final p = feed(Calibrator(), frames);
    expect(p.issue, CalibrationIssue.notCentered);
    expect(p.result, isNull);
  });

  test(
    'a short missing stretch (5 frames, 165 ms) does not reset the hold',
    () {
      final c = Calibrator();
      feed(c, standingSequence(duration: const Duration(seconds: 1)));
      for (var i = 0; i < 5; i++) {
        final r = c.add(
          PoseFrame(const [], Duration(milliseconds: 1000 + i * 33)),
        );
        expect(r.issue, isNull);
      }
      final p = c.add(
        PoseFrame([makePose()], const Duration(milliseconds: 1200)),
      );
      expect(p.progress, greaterThan(0.5));
      Calibration? result;
      for (final f in standingSequence(
        duration: const Duration(seconds: 1),
        start: const Duration(milliseconds: 1233),
      )) {
        result ??= c.add(f).result;
      }
      expect(result, isNotNull);
    },
  );

  test('a missing stretch longer than maxBadGap resets the hold', () {
    final c = Calibrator();
    feed(c, standingSequence(duration: const Duration(seconds: 1)));
    CalibrationProgress r = const CalibrationProgress(progress: 1);
    for (var i = 0; i < 9; i++) {
      r = c.add(PoseFrame(const [], Duration(milliseconds: 1000 + i * 33)));
    }
    expect(r.issue, CalibrationIssue.noPerson);
    expect(r.progress, 0);
    final p = c.add(
      PoseFrame([makePose()], const Duration(milliseconds: 1300)),
    );
    expect(p.progress, lessThan(0.1));
  });

  test('hip jitter of +-0.01 over 2 s still calibrates', () {
    final frames = poseSequence(
      duration: const Duration(seconds: 2),
      posesAt: (t) {
        final i = t.inMilliseconds ~/ 33;
        return [makePose(hipY: 0.6 + (i.isEven ? 0.01 : -0.01))];
      },
    );
    final p = feed(Calibrator(), frames);
    expect(p.result, isNotNull);
    expect(p.issue, isNull);
  });

  test('swaying beyond 0.08 torso is still notStill', () {
    final frames = poseSequence(
      duration: const Duration(seconds: 2),
      posesAt: (t) => [
        makePose(
          hipY: 0.6 + (t.inMilliseconds ~/ 100 % 2 == 0 ? 0.015 : -0.015),
        ),
      ],
    );
    expect(feed(Calibrator(), frames).issue, CalibrationIssue.notStill);
  });

  test('two people in swapped list order: the centred one is calibrated', () {
    final frames = poseSequence(
      duration: const Duration(seconds: 2),
      posesAt: (t) {
        final centred = makePose(hipX: 0.5);
        final side = makePose(hipX: 0.8);
        return t.inMilliseconds ~/ 33 % 2 == 0
            ? [centred, side]
            : [side, centred];
      },
    );
    final p = feed(Calibrator(), frames);
    expect(p.result, isNotNull);
    expect(p.result!.centerX, closeTo(0.5, 0.01));
  });

  test('wrists present do not affect calibration', () {
    final frames = poseSequence(
      duration: const Duration(seconds: 2),
      posesAt: (_) => [
        makePose(
          leftWrist: const Offset(0.3, 0.5),
          rightWrist: const Offset(0.7, 0.5),
        ),
      ],
    );
    expect(feed(Calibrator(), frames).result, isNotNull);
  });

  group('15 fps (single-pose plugin) and timestamps', () {
    test('2 s of still frames at 15 fps calibrates', () {
      final c = Calibrator();
      Calibration? result;
      int? finishedAtMs;
      for (final f in standingSequence(
        duration: const Duration(milliseconds: 2400),
        fps: 15,
        noise: 0.002,
      )) {
        final p = c.add(f);
        if (p.result != null && result == null) {
          result = p.result;
          finishedAtMs = f.timestamp.inMilliseconds;
        }
      }
      expect(result, isNotNull);
      expect(finishedAtMs, inInclusiveRange(1900, 2100));
      expect(result!.torsoHeight, closeTo(0.3, 0.005));
    });

    test('progress at 15 fps is time-based (1 s -> about half)', () {
      final c = Calibrator();
      late CalibrationProgress mid;
      for (final f in standingSequence(
        duration: const Duration(seconds: 1),
        fps: 15,
      )) {
        mid = c.add(f);
      }
      expect(mid.progress, inInclusiveRange(0.45, 0.6));
    });

    test('one dropped frame at 15 fps (133 ms gap) does not reset', () {
      final c = Calibrator();
      final frames = standingSequence(
        duration: const Duration(milliseconds: 2400),
        fps: 15,
      );
      Calibration? result;
      for (var i = 0; i < frames.length; i++) {
        final f = i == 10
            ? PoseFrame(const [], frames[i].timestamp)
            : frames[i];
        result ??= c.add(f).result;
      }
      expect(result, isNotNull);
    });

    test('a 150 ms missing stretch at 60 fps (9 frames) does not reset', () {
      final c = Calibrator();
      feed(c, standingSequence(duration: const Duration(seconds: 1), fps: 60));
      for (var i = 0; i < 9; i++) {
        final r = c.add(
          PoseFrame(const [], Duration(milliseconds: 1000 + i * 17)),
        );
        expect(r.issue, isNull);
      }
    });

    test('a missing stretch of 300 ms resets even at 15 fps', () {
      final c = Calibrator();
      feed(c, standingSequence(duration: const Duration(seconds: 1), fps: 15));
      CalibrationProgress r = const CalibrationProgress(progress: 1);
      for (var t = 1000; t <= 1400; t += 67) {
        r = c.add(PoseFrame(const [], Duration(milliseconds: t)));
      }
      expect(r.issue, CalibrationIssue.noPerson);
    });

    test('a > 2 s frame gap does not calibrate from two frames', () {
      final c = Calibrator();
      final first = c.add(PoseFrame([makePose()], Duration.zero));
      expect(first.result, isNull);
      final second = c.add(
        PoseFrame([makePose()], const Duration(milliseconds: 2500)),
      );
      expect(second.result, isNull);
      expect(second.issue, isNull);
      expect(second.progress, lessThan(1.0));
      // It needs at least minSamples frames in total.
      CalibrationProgress last = second;
      var n = 2;
      for (var t = 2533; last.result == null && n < 20; t += 33, n++) {
        last = c.add(PoseFrame([makePose()], Duration(milliseconds: t)));
      }
      expect(n, Calibrator.minSamples);
      expect(last.result, isNotNull);
    });
  });
}
