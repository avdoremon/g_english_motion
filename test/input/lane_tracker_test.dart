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

    test('resyncs to the actual x on the next update (no hysteresis lag)', () {
      final t = _tracker(laneCount: 3);
      t.update(_at(0.5), _ms(0));
      expect(t.current, 1);
      t.setLaneCount(5);
      // 5 lanes of 0.18: lane edges at 0.05, 0.23, 0.41, 0.59, 0.77, 0.95.
      // The player stands at 0.80 -> lane 4 straight away, not 1 -> 2 -> ...
      expect(t.update(_at(0.80), _ms(33)), 4);
      expect(t.current, 4);
    });

    test('resync lands on the exact lane even inside the hysteresis band', () {
      final t = _tracker(laneCount: 5);
      t.update(_at(0.95), _ms(0));
      expect(t.current, 4);
      t.setLaneCount(3);
      expect(t.current, 2); // clamped placeholder
      // 0.58 is lane 1 (edge at 0.59) but within the hysteresis band of 2.
      expect(t.update(_at(0.58), _ms(33)), 1);
    });

    test('resync waits for a usable pose', () {
      final t = _tracker(laneCount: 3);
      t.update(_at(0.5), _ms(0));
      t.setLaneCount(5);
      expect(t.update(makePose(confidence: 0.1), _ms(33)), 1); // clamped keep
      expect(t.update(_at(0.80), _ms(66)), 4);
    });

    test('history from the old layout is discarded', () {
      final t = _tracker(laneCount: 3);
      t.update(_at(0.5), _ms(0));
      t.update(_at(0.7), _ms(100)); // lane 2 of 3
      t.setLaneCount(5);
      t.update(_at(0.5), _ms(200)); // resync: lane 2 of 5
      // Before the change the lane was never 2-of-3 in the new layout:
      // every query now answers in the new layout.
      expect(t.laneAt(_ms(50)), t.laneAt(_ms(250)));
      expect(t.laneAt(_ms(250)), 2);
    });

    test('same count is a no-op for history', () {
      final t = _tracker(laneCount: 3);
      t.update(_at(0.5), _ms(0));
      t.update(_at(0.7), _ms(100));
      t.setLaneCount(3);
      expect(t.laneAt(_ms(50)), 1);
      expect(t.laneAt(_ms(150)), 2);
    });
  });

  group('initial lane', () {
    test('is laneCount ~/ 2 for every count', () {
      for (var n = 1; n <= 8; n++) {
        expect(_tracker(laneCount: n).current, n ~/ 2, reason: '$n lanes');
      }
    });

    test(
      'even count with a centre exactly on a lane edge is deterministic',
      () {
        // centre 0.5 + 4 lanes: the centre is a lane edge (float-sensitive
        // before); the initial lane is explicitly the upper middle lane.
        expect(_tracker(laneCount: 4).current, 2);
        expect(_tracker(laneCount: 2).current, 1);
      },
    );
  });

  group('history edge cases', () {
    test('laneAt before any update is the initial lane', () {
      final t = _tracker();
      expect(t.laneAt(_ms(0)), 1);
      expect(t.laneAt(_ms(-500)), 1);
      expect(t.laneAt(_ms(10000)), 1);
    });

    test('a query older than the history window answers with the lane at '
        'the start of the window', () {
      final t = _tracker();
      t.update(_at(0.5), _ms(0));
      t.update(_at(0.7), _ms(100)); // -> lane 2
      for (var ms = 133; ms <= 3000; ms += 67) {
        t.update(_at(0.7), _ms(ms));
      }
      // The change at 100 ms was pruned (window 1.5 s): the oldest retained
      // knowledge is lane 2; the query must not throw or return garbage.
      expect(t.laneAt(_ms(50)), 2);
      expect(t.laneAt(_ms(3000)), 2);
    });

    test('a multi-lane skip in one update is recorded as a single change', () {
      final t = _tracker(laneCount: 5);
      t.update(_at(0.5), _ms(0));
      expect(t.current, 2);
      expect(t.update(_at(0.95), _ms(67)), 4);
      expect(t.laneAt(_ms(50)), 2);
      expect(t.laneAt(_ms(67)), 4);
      expect(t.update(_at(0.05), _ms(134)), 0);
      expect(t.laneAt(_ms(100)), 4);
      expect(t.laneAt(_ms(134)), 0);
    });

    test('downward move needs the hysteresis margin (+- at the boundary)', () {
      // Boundary lane1|lane2 at 0.59, hysteresis 0.1 * 0.18 = 0.018.
      LaneTracker atLane2() {
        final t = _tracker();
        t.update(_at(0.7), _ms(0));
        expect(t.current, 2);
        return t;
      }

      expect(atLane2().update(_at(0.59 - 0.016), _ms(33)), 2);
      expect(atLane2().update(_at(0.59 - 0.020), _ms(33)), 1);
      // Upward at the matching boundary from lane 1.
      LaneTracker atLane1() {
        final t = _tracker();
        t.update(_at(0.5), _ms(0));
        return t;
      }

      expect(atLane1().update(_at(0.59 + 0.016), _ms(33)), 1);
      expect(atLane1().update(_at(0.59 + 0.020), _ms(33)), 2);
    });

    test('a downward move across several lanes lands on the right lane', () {
      final t = _tracker(laneCount: 5);
      t.update(_at(0.95), _ms(0));
      expect(t.current, 4);
      expect(t.update(_at(0.3), _ms(67)), 1);
    });
  });

  group('mirror with a centre away from 0.5', () {
    const calib = Calibration(
      torsoHeight: 0.3,
      centerX: 0.3,
      baselineHipY: 0.6,
      baselineShoulderY: 0.3,
    );
    LaneTracker tracker() =>
        LaneTracker(calib, laneCount: 3, mirror: true, aspectRatio: 1.0);

    // Mirrored centre = 0.7; lane edges (width 0.18): 0.43, 0.61, 0.79, 0.97.
    test('the calibrated spot is the middle lane', () {
      expect(tracker().update(_at(0.3), _ms(0)), 1);
    });

    test('raw x to the right of the spot is the lower lane', () {
      // raw 0.5 -> mirrored 0.5 -> lane 0
      expect(tracker().update(_at(0.5), _ms(0)), 0);
    });

    test('raw x to the left of the spot is the higher lane', () {
      // raw 0.1 -> mirrored 0.9 -> lane 2
      expect(tracker().update(_at(0.1), _ms(0)), 2);
    });
  });

  group('15 fps (single-pose plugin)', () {
    test('lane changes are detected and laneAt works on 67 ms frames', () {
      final t = _tracker();
      final changes = <int>[];
      var lane = t.current;
      for (var i = 0; i < 45; i++) {
        final ms = (i * 1000 / 15).round();
        final x = ms < 1000 ? 0.5 : (ms < 2000 ? 0.7 : 0.3);
        final next = t.update(_at(x), _ms(ms));
        if (next != lane) {
          changes.add(next);
          lane = next;
        }
      }
      expect(changes, [2, 0]);
      expect(t.laneAt(_ms(1900)), 2);
      expect(t.laneAt(_ms(2100)), 0);
    });
  });
}
