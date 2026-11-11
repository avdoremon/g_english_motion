import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/calibrator.dart';
import 'package:g_english_motion/input/pose_types.dart';
import 'package:g_english_motion/input/squat_detector.dart';

import '../helpers/synthetic_poses.dart';

Duration ms(int v) => Duration(milliseconds: v);

const cal = Calibration(
  torsoHeight: 0.3,
  centerX: 0.5,
  baselineHipY: 0.6,
  baselineShoulderY: 0.3,
);

Pose stand() => makePose();
Pose drop(double torsos) => makePose(hipY: 0.6 + torsos * 0.3, kneeY: 0.7);

int run(SquatDetector d, Pose pose, int from, int to) {
  var n = 0;
  for (var t = from; t <= to; t += 33) {
    if (d.update(pose, ms(t))) n++;
  }
  return n;
}

void main() {
  test('a 0.3 torso drop held 300 ms fires once', () {
    final d = SquatDetector(cal);
    expect(run(d, drop(0.3), 0, 2000), 1);
  });

  test('200 ms is not enough', () {
    final d = SquatDetector(cal);
    expect(run(d, drop(0.3), 0, 200), 0);
  });

  test('a 0.15 torso drop never fires', () {
    final d = SquatDetector(cal);
    expect(run(d, drop(0.15), 0, 3000), 0);
  });

  test(
    'a dropout shorter than the grace neither restarts nor double fires',
    () {
      final d = SquatDetector(cal);
      expect(run(d, drop(0.3), 0, 200), 0);
      final missing = Pose({
        for (final e in drop(0.3).joints.entries)
          if (e.key != PoseJoint.leftHip) e.key: e.value,
      });
      expect(d.update(missing, ms(233)), isFalse);
      final fires = <int>[];
      for (var t = 266; t <= 1500; t += 33) {
        if (d.update(drop(0.3), ms(t))) fires.add(t);
      }
      // The hold counts from the first frame at 0 ms: fires at 332 ms (first frame past 300 ms).
      expect(fires, [332]);
    },
  );

  test('a dropout longer than the grace restarts the hold, never fires', () {
    final d = SquatDetector(cal);
    run(d, drop(0.3), 0, 200);
    final missing = Pose({});
    expect(d.update(missing, ms(500)), isFalse);
    expect(d.update(drop(0.3), ms(533)), isFalse);
    expect(d.update(drop(0.3), ms(700)), isFalse);
    expect(d.update(drop(0.3), ms(833)), isTrue);
  });

  test('a long dropout while squatting does not re-fire (latch)', () {
    final d = SquatDetector(cal);
    expect(run(d, drop(0.3), 0, 600), 1);
    d.update(Pose({}), ms(1000));
    expect(run(d, drop(0.3), 2000, 4000), 0);
  });

  test('standing back up re-arms', () {
    final d = SquatDetector(cal);
    expect(run(d, drop(0.3), 0, 600), 1);
    run(d, stand(), 700, 900);
    expect(run(d, drop(0.3), 1000, 1600), 1);
  });

  test('between release and drop does not re-arm', () {
    final d = SquatDetector(cal);
    expect(run(d, drop(0.3), 0, 600), 1);
    run(d, drop(0.18), 700, 900);
    expect(run(d, drop(0.3), 1000, 1600), 0);
  });

  test('reset clears hold but keeps nothing pending', () {
    final d = SquatDetector(cal);
    run(d, drop(0.3), 0, 200);
    d.reset();
    expect(d.update(drop(0.3), ms(233)), isFalse);
    expect(run(d, drop(0.3), 266, 700), 1);
  });

  test('rebaseline moves the baseline and clears hold and latch', () {
    final d = SquatDetector(cal);
    expect(run(d, drop(0.3), 0, 600), 1);
    // Player now rests where the old baseline reads as a deep squat.
    d.rebaseline(drop(0.3));
    expect(run(d, drop(0.3), 700, 2000), 0);
    // A real drop from the new baseline fires.
    expect(run(d, makePose(hipY: 0.69 + 0.1), 2100, 2800), 1);
  });
}
