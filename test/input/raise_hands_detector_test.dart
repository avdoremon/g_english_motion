import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/pose_types.dart';
import 'package:g_english_motion/input/raise_hands_detector.dart';

import '../helpers/synthetic_poses.dart';

Duration ms(int v) => Duration(milliseconds: v);

// Default nose y = 0.6 - 0.3 - 0.1 = 0.2.
Pose both() => makePose(
  leftWrist: const Offset(0.3, 0.1),
  rightWrist: const Offset(0.7, 0.1),
);
Pose one() => makePose(
  leftWrist: const Offset(0.3, 0.1),
  rightWrist: const Offset(0.7, 0.5),
);
Pose down() => makePose(
  leftWrist: const Offset(0.3, 0.5),
  rightWrist: const Offset(0.7, 0.5),
);

/// Feeds [pose] every 33 ms from [from] to [to] ms; returns events seen.
int run(RaiseHandsDetector d, Pose pose, int from, int to) {
  var n = 0;
  for (var t = from; t <= to; t += 33) {
    if (d.update(pose, ms(t))) n++;
  }
  return n;
}

void main() {
  test('both hands up for 500 ms fires once', () {
    final d = RaiseHandsDetector();
    expect(run(d, both(), 0, 1000), 1);
  });

  test('400 ms is not enough', () {
    final d = RaiseHandsDetector();
    expect(run(d, both(), 0, 400), 0);
  });

  test('a single hand never fires', () {
    final d = RaiseHandsDetector();
    expect(run(d, one(), 0, 2000), 0);
  });

  test('missing wrists never fire', () {
    final d = RaiseHandsDetector();
    expect(run(d, makePose(), 0, 2000), 0);
  });

  test('lower then raise again fires again', () {
    final d = RaiseHandsDetector();
    expect(run(d, both(), 0, 700), 1);
    expect(run(d, down(), 733, 900), 0);
    expect(run(d, both(), 933, 1700), 1);
  });

  test('interrupted raise restarts the hold', () {
    final d = RaiseHandsDetector();
    expect(run(d, both(), 0, 330), 0);
    expect(run(d, down(), 363, 400), 0);
    expect(run(d, both(), 433, 800), 0); // only ~370 ms since restart
  });
}
