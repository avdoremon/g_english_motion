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
}
