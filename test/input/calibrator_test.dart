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

  test('losing the person resets the hold', () {
    final c = Calibrator();
    final a = standingSequence(duration: const Duration(seconds: 1));
    feed(c, a);
    c.add(const PoseFrame([], Duration(milliseconds: 1100)));
    final p = c.add(
      PoseFrame([makePose()], const Duration(milliseconds: 1200)),
    );
    expect(p.progress, lessThan(0.1));
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
}
