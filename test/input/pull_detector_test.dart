import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/calibrator.dart';
import 'package:g_english_motion/input/pull_detector.dart';
import 'package:g_english_motion/input/pose_types.dart';

import '../helpers/synthetic_poses.dart';

const cal = Calibration(
  torsoHeight: 0.3,
  centerX: 0.5,
  baselineHipY: 0.6,
  baselineShoulderY: 0.3,
);

Duration ms(int v) => Duration(milliseconds: v);

/// Feeds a left/right wrist y(t) at 30 fps; returns the hands reported and
/// when.
List<(Hand, Duration)> feed(
  PullDetector d,
  Duration duration, {
  double Function(Duration t)? left,
  double Function(Duration t)? right,
}) {
  final out = <(Hand, Duration)>[];
  for (final f in poseSequence(
    duration: duration,
    posesAt: (t) => [
      makePose(
        leftWrist: left == null ? null : Offset(0.4, left(t)),
        rightWrist: right == null ? null : Offset(0.6, right(t)),
      ),
    ],
  )) {
    final h = d.update(f.poses.first, f.timestamp);
    if (h != null) out.add((h, f.timestamp));
  }
  return out;
}

/// One pull: from [top] down by [travel] over 300 ms, back up over 300 ms.
double Function(Duration) stroke({
  double top = 0.3,
  double travel = 0.15,
  int start = 200,
}) => (t) {
  final s = t.inMilliseconds - start;
  if (s < 0) return top;
  if (s < 300) return top + travel * s / 300;
  if (s < 600) return top + travel * (1 - (s - 300) / 300);
  return top;
};

void main() {
  test('a left-hand pull (down 0.15, then up) reports left once', () {
    final d = PullDetector(cal);
    final res = feed(d, ms(1200), left: stroke());
    expect(res.map((r) => r.$1), [Hand.left]);
    // Reported on the way up, not before the hand went down.
    expect(res.single.$2, greaterThan(ms(500)));
  });

  test('a right-hand pull reports right', () {
    final d = PullDetector(cal);
    expect(feed(d, ms(1200), right: stroke()).map((r) => r.$1), [Hand.right]);
  });

  test('a small movement (0.05) is not a pull', () {
    final d = PullDetector(cal);
    expect(feed(d, ms(1200), left: stroke(travel: 0.05)), isEmpty);
  });

  test('going down without coming back up is not a pull', () {
    final d = PullDetector(cal);
    final res = feed(
      d,
      ms(1500),
      left: (t) => 0.3 + (t.inMilliseconds > 200 ? 0.2 : 0),
    );
    expect(res, isEmpty);
  });

  test('a slow lowering of the arm is not a pull', () {
    final d = PullDetector(cal);
    final res = feed(
      d,
      ms(6000),
      left: (t) => 0.3 + 0.2 * t.inMilliseconds / 6000,
    );
    expect(res, isEmpty);
    // ...and neither is the slow raise afterwards.
    expect(
      feed(d, ms(6000), left: (t) => 0.5 - 0.2 * t.inMilliseconds / 6000),
      isEmpty,
    );
  });

  test('alternating hands report left, right, left, right', () {
    final d = PullDetector(cal);
    final res = feed(
      d,
      ms(2800),
      left: (t) => stroke(start: 200)(t) + stroke(start: 1600)(t) - 0.3,
      right: (t) => stroke(start: 900)(t) + stroke(start: 2300)(t) - 0.3,
    );
    expect(res.map((r) => r.$1), [
      Hand.left,
      Hand.right,
      Hand.left,
      Hand.right,
    ]);
  });

  test('three pulls of the same hand report three times', () {
    final d = PullDetector(cal);
    final res = feed(
      d,
      ms(3000),
      left: (t) =>
          stroke(start: 200)(t) +
          stroke(start: 1000)(t) +
          stroke(start: 1800)(t) -
          0.6,
    );
    expect(res.map((r) => r.$1), [Hand.left, Hand.left, Hand.left]);
  });

  test('both hands pulling together report both, one per update', () {
    final d = PullDetector(cal);
    final res = feed(d, ms(1200), left: stroke(), right: stroke());
    expect(res.map((r) => r.$1).toSet(), {Hand.left, Hand.right});
    expect(res, hasLength(2));
  });

  test('an unreliable wrist never counts', () {
    final d = PullDetector(cal);
    var fired = false;
    for (final f in poseSequence(
      duration: ms(1200),
      posesAt: (t) {
        final p = makePose(leftWrist: Offset(0.4, stroke()(t)));
        return [
          Pose({
            ...p.joints,
            PoseJoint.leftWrist: Landmark(0.4, stroke()(t), 0.2),
          }),
        ];
      },
    )) {
      fired |= d.update(f.poses.first, f.timestamp) != null;
    }
    expect(fired, isFalse);
  });

  test('minTravel scales with the torso', () {
    final d = PullDetector(cal, minTravel: 0.8); // 0.24 needed
    expect(feed(d, ms(1200), left: stroke(travel: 0.15)), isEmpty);
  });
}
