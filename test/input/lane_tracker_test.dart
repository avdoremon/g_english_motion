import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/calibrator.dart';
import 'package:g_english_motion/input/lane_tracker.dart';
import 'package:g_english_motion/input/pose_types.dart';

import '../helpers/synthetic_poses.dart';

const _calib = Calibration(
  torsoHeight: 0.3,
  centerX: 0.5,
  baselineHipY: 0.6,
  baselineShoulderY: 0.3,
);

Pose _at(double x) => makePose(hipX: x);
Duration _ms(int ms) => Duration(milliseconds: ms);

// These cases assume equal x/y scales (aspect 1.0): lane width in x is then
// 0.6 * 0.3 = 0.18. The 16:9 behaviour is covered in the aspect group below.
LaneTracker _tracker({int laneCount = 3, bool mirror = false}) =>
    LaneTracker(_calib, laneCount: laneCount, mirror: mirror, aspectRatio: 1.0);

void main() {
  group('lane mapping (3 lanes, no mirror)', () {
    final cases = {0.5: 1, 0.30: 0, 0.70: 2, 0.0: 0, 1.0: 2};
    cases.forEach((x, lane) {
      test('x $x -> lane $lane', () {
        expect(_tracker().update(_at(x), _ms(0)), lane);
      });
    });

    test('initial lane is the middle lane', () {
      expect(_tracker().current, 1);
      expect(_tracker(laneCount: 4).current, 2);
    });
  });

  group('4 lanes', () {
    test('x 0.41 -> 1 and 0.59 -> 2', () {
      expect(_tracker(laneCount: 4).update(_at(0.41), _ms(0)), 1);
      expect(_tracker(laneCount: 4).update(_at(0.59), _ms(0)), 2);
    });
  });

  group('hysteresis', () {
    // 3 lanes: boundary between lane 1 and 2 is 0.5 + 0.09 = 0.59.
    test('just past boundary stays, well past switches', () {
      final t = _tracker();
      t.update(_at(0.5), _ms(0));
      expect(t.update(_at(0.60), _ms(33)), 1);
      expect(t.update(_at(0.62), _ms(66)), 2);
    });

    test('moving back needs to pass the boundary by hysteresis too', () {
      final t = _tracker();
      t.update(_at(0.7), _ms(0));
      expect(t.current, 2);
      expect(t.update(_at(0.58), _ms(33)), 2);
      expect(t.update(_at(0.56), _ms(66)), 1);
    });
  });

  group('aspect ratio (torso is a fraction of height, x of width)', () {
    test('default is 16:9 and lane width is 0.6 * torso / aspect', () {
      expect(PoseFrame.defaultAspectRatio, closeTo(16 / 9, 1e-9));
      final width = 0.6 * 0.3 / (16 / 9); // 0.10125
      final t = LaneTracker(_calib, laneCount: 3, mirror: false);
      // Lane 1 spans centre +- width/2; just inside stays, beyond moves.
      expect(t.update(_at(0.5 + width * 0.4), _ms(0)), 1);
      final t2 = LaneTracker(_calib, laneCount: 3, mirror: false);
      expect(t2.update(_at(0.5 + width * 1.6), _ms(0)), 2);
      // With the old (aspect-blind) 0.18 width this x would still be lane 1.
      final t3 = LaneTracker(_calib, laneCount: 3, mirror: false);
      expect(t3.update(_at(0.5 + 0.18 * 0.9), _ms(0)), 2);
    });

    test('the latest aspect ratio is used (rotation)', () {
      final t = LaneTracker(_calib, laneCount: 3, mirror: false)
        ..aspectRatio = 1.0;
      expect(t.update(_at(0.5 + 0.18 * 0.4), _ms(0)), 1);
      t.aspectRatio = 16 / 9;
      expect(t.update(_at(0.5 + 0.18 * 0.4), _ms(33)), 2);
    });
  });

  group('mirror', () {
    test('x 0.30 -> lane 2', () {
      final t = _tracker(mirror: true);
      expect(t.update(_at(0.30), _ms(0)), 2);
    });
  });

  test('lost pose keeps the current lane', () {
    final t = _tracker();
    t.update(_at(0.3), _ms(0));
    expect(t.update(makePose(confidence: 0.1), _ms(33)), 0);
  });

  group('laneAt', () {
    test('returns lane before the change for earlier times', () {
      final t = _tracker();
      t.update(_at(0.5), _ms(0));
      t.update(_at(0.5), _ms(500));
      t.update(_at(0.7), _ms(1000));
      expect(t.current, 2);
      expect(t.laneAt(_ms(800)), 1);
      expect(t.laneAt(_ms(1000)), 2);
      expect(t.laneAt(_ms(1200)), 2);
    });

    test('history over 1 s is available', () {
      final t = _tracker();
      t.update(_at(0.5), _ms(0));
      t.update(_at(0.7), _ms(100));
      for (var ms = 133; ms <= 1100; ms += 33) {
        t.update(_at(0.7), _ms(ms));
      }
      expect(t.laneAt(_ms(50)), 1);
      expect(t.laneAt(_ms(1000)), 2);
    });
  });

  group('setLaneCount', () {
    test('changes count without throwing and clamps lane', () {
      final t = _tracker();
      t.update(_at(0.9), _ms(0));
      expect(t.current, 2);
      expect(() => t.setLaneCount(4), returnsNormally);
      expect(t.update(_at(0.9), _ms(33)), 3);
      t.setLaneCount(2);
      expect(t.current, 1);
      expect(t.laneAt(_ms(0)), inInclusiveRange(0, 1));
    });
  });
}
