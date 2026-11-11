import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/input/one_euro_filter.dart';
import 'package:g_english_motion/input/pose_types.dart';

import '../helpers/synthetic_poses.dart';

Duration frame(int i) => Duration(microseconds: (i * 1000000 / 30).round());

void main() {
  group('OneEuroFilter', () {
    test('constant input stays constant', () {
      final f = OneEuroFilter();
      for (var i = 0; i < 60; i++) {
        expect(f.filter(0.5, frame(i)), closeTo(0.5, 1e-9));
      }
    });

    test('first sample returns itself', () {
      expect(OneEuroFilter().filter(0.73, Duration.zero), 0.73);
    });

    test('noise +/-0.02 around 0.5 is attenuated below 0.01', () {
      final f = OneEuroFilter();
      var minV = 1.0, maxV = 0.0;
      for (var i = 0; i < 120; i++) {
        final v = f.filter(0.5 + (i.isEven ? 0.02 : -0.02), frame(i));
        if (i >= 30) {
          if (v < minV) minV = v;
          if (v > maxV) maxV = v;
        }
      }
      expect(maxV - minV, lessThan(0.01));
    });

    test('step 0.5 -> 0.6 reaches >0.59 within 200 ms at 30 fps', () {
      final f = OneEuroFilter();
      var i = 0;
      for (; i < 30; i++) {
        f.filter(0.5, frame(i));
      }
      final start = frame(i);
      double last = 0;
      while (frame(i) - start <= const Duration(milliseconds: 200)) {
        last = f.filter(0.6, frame(i));
        i++;
      }
      expect(last, greaterThan(0.59));
    });

    test('non-positive dt does not produce NaN; reset restarts', () {
      final f = OneEuroFilter();
      f.filter(0.5, const Duration(milliseconds: 100));
      final v = f.filter(0.7, const Duration(milliseconds: 100));
      expect(v.isFinite, isTrue);
      f.reset();
      expect(f.filter(0.2, Duration.zero), 0.2);
    });
  });

  group('Pose', () {
    test('torsoHeight = 0.3 with shoulders 0.3 and hips 0.6', () {
      final p = makePose(hipY: 0.6, torso: 0.3);
      expect(p.torsoHeight, closeTo(0.3, 1e-9));
      expect(p.midShoulderY, closeTo(0.3, 1e-9));
      expect(p.midHipY, closeTo(0.6, 1e-9));
      expect(p.midHipX, closeTo(0.5, 1e-9));
    });

    test('null when leftHip confidence is 0.3', () {
      final p = Pose({
        ...makePose().joints,
        PoseJoint.leftHip: const Landmark(0.45, 0.6, 0.3),
      });
      expect(p.torsoHeight, isNull);
      expect(p.midHipY, isNull);
      expect(p.midHipX, isNull);
      expect(p.midShoulderY, isNotNull);
    });

    test('null when joint missing', () {
      final joints = Map.of(makePose().joints)..remove(PoseJoint.rightShoulder);
      expect(Pose(joints).midShoulderY, isNull);
    });
  });

  test('events carry at and are exhaustively switchable', () {
    final events = <GameInputEvent>[
      const LaneChanged(1, at: Duration(seconds: 1)),
      const Confirmed(2, at: Duration(seconds: 1)),
      const CursorMoved(0.1, 0.2, at: Duration(seconds: 1)),
      const Pulled(Hand.left, at: Duration(seconds: 1)),
      const HandRaised(Hand.left, at: Duration(seconds: 1)),
      const PlayerLost(at: Duration(seconds: 1)),
      const PlayerFound(at: Duration(seconds: 1)),
    ];
    for (final e in events) {
      final s = switch (e) {
        LaneChanged() => 'lane',
        Confirmed() => 'confirm',
        CursorMoved() => 'cursor',
        Pulled() => 'pull',
        HandRaised() => 'hand',
        PlayerLost() => 'lost',
        PlayerFound() => 'found',
      };
      expect(s, isNotEmpty);
      expect(e.at, const Duration(seconds: 1));
    }
    const frameObj = PoseFrame([], Duration.zero);
    expect(frameObj.poses, isEmpty);
  });
}
