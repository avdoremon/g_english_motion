
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/calibrator.dart';
import 'package:g_english_motion/input/cursor_tracker.dart';
import 'package:g_english_motion/input/pose_types.dart';

import '../helpers/synthetic_poses.dart';

const cal = Calibration(
  torsoHeight: 0.3,
  centerX: 0.5,
  baselineHipY: 0.6,
  baselineShoulderY: 0.3,
);
const t0 = Duration.zero;

Pose pose({Offset? left, Offset? right}) =>
    makePose(leftWrist: left, rightWrist: right);

void main() {
  test('the higher wrist is the active hand', () {
    final c = CursorTracker(cal, mirror: false);
    expect(c.activeHand, isNull);
    c.update(
      pose(left: const Offset(0.4, 0.5), right: const Offset(0.6, 0.3)),
      t0,
    );
    expect(c.activeHand, Hand.right);
  });

  test('the other hand needs to be higher by more than the margin', () {
    final c = CursorTracker(cal, mirror: false);
    c.update(
      pose(left: const Offset(0.4, 0.5), right: const Offset(0.6, 0.3)),
      t0,
    );
    // Left higher by 0.03: stays right.
    c.update(
      pose(left: const Offset(0.4, 0.27), right: const Offset(0.6, 0.3)),
      t0,
    );
    expect(c.activeHand, Hand.right);
    // Left higher by 0.08: switches.
    c.update(
      pose(left: const Offset(0.4, 0.22), right: const Offset(0.6, 0.3)),
      t0,
    );
    expect(c.activeHand, Hand.left);
    // Right only slightly higher again: stays left.
    c.update(
      pose(left: const Offset(0.4, 0.3), right: const Offset(0.6, 0.27)),
      t0,
    );
    expect(c.activeHand, Hand.left);
  });

  test('a single reliable wrist is used; an unreliable one is not', () {
    final c = CursorTracker(cal, mirror: false);
    c.update(pose(right: const Offset(0.6, 0.3)), t0);
    expect(c.activeHand, Hand.right);
    final p = pose(left: const Offset(0.4, 0.2), right: const Offset(0.6, 0.3));
    final low = Pose({
      ...p.joints,
      PoseJoint.leftWrist: const Landmark(0.4, 0.2, 0.2),
    });
    c.update(low, t0);
    expect(c.activeHand, Hand.right, reason: 'a doubtful wrist is ignored');
  });

  test('wrist at the right edge of the reach box maps to x = 1', () {
    final c = CursorTracker(cal, mirror: false);
    // centerX 0.5 + 0.9 * 0.3 = 0.77
    final r = c.update(pose(right: const Offset(0.77, 0.4)), t0)!;
    expect(r.$1, closeTo(1.0, 1e-9));
    final l = c.update(pose(right: const Offset(0.23, 0.4)), t0)!;
    expect(l.$1, closeTo(0.0, 1e-9));
    final m = c.update(pose(right: const Offset(0.5, 0.4)), t0)!;
    expect(m.$1, closeTo(0.5, 1e-9));
  });

  test('mirror flips x', () {
    final c = CursorTracker(cal);
    final r = c.update(pose(right: const Offset(0.77, 0.4)), t0)!;
    expect(r.$1, closeTo(0.0, 1e-9));
  });

  test('y runs from above the nose to the hip line', () {
    final c = CursorTracker(cal, mirror: false);
    // nose.y = 0.3 - 0.1 = 0.2 -> top 0.2 - 0.09 = 0.11; hip 0.6.
    final top = c.update(pose(right: const Offset(0.5, 0.11)), t0)!;
    expect(top.$2, closeTo(0.0, 1e-9));
    final bottom = c.update(pose(right: const Offset(0.5, 0.6)), t0)!;
    expect(bottom.$2, closeTo(1.0, 1e-9));
    final above = c.update(pose(right: const Offset(0.5, 0.0)), t0)!;
    expect(above.$2, 0.0, reason: 'clamped');
  });

  test('no visible wrist -> null', () {
    final c = CursorTracker(cal, mirror: false);
    expect(c.update(pose(), t0), isNull);
  });

  test('the frame aspect ratio narrows the horizontal reach', () {
    final c = CursorTracker(cal, mirror: false, aspectRatio: 2);
    // half reach = 0.9 * 0.3 / 2 = 0.135 -> 0.635 is the edge.
    final r = c.update(pose(right: const Offset(0.635, 0.4)), t0)!;
    expect(r.$1, closeTo(1.0, 1e-9));
  });
}
