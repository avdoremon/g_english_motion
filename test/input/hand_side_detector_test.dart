import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/hand_side_detector.dart';
import 'package:g_english_motion/input/pose_types.dart';

import '../helpers/synthetic_poses.dart';

Duration ms(int v) => Duration(milliseconds: v);

// Default nose y = 0.6 - 0.3 - 0.1 = 0.2.
const _up = Offset(0.5, 0.1);
const _dn = Offset(0.5, 0.5);

Pose leftOnly() => makePose(leftWrist: _up, rightWrist: _dn);
Pose rightOnly() => makePose(leftWrist: _dn, rightWrist: _up);
Pose both() => makePose(leftWrist: _up, rightWrist: _up);
Pose down() => makePose(leftWrist: _dn, rightWrist: _dn);

/// Left up, right wrist missing entirely (unreliable).
Pose leftUpRightMissing() => makePose(leftWrist: _up);

/// Feeds (t, pose) pairs; returns (t, hand) for each event.
List<(int, Hand)> feed(HandSideDetector d, Iterable<(int, Pose)> frames) => [
  for (final (t, p) in frames)
    if (d.update(p, ms(t)) case final Hand h) (t, h),
];

Iterable<(int, Pose)> every(Pose p, int from, int to, [int step = 33]) => [
  for (var t = from; t <= to; t += step) (t, p),
];

void main() {
  test('left alone above the nose for 500 ms fires Hand.left once', () {
    final fired = feed(HandSideDetector(), every(leftOnly(), 0, 2000));
    expect(fired.map((e) => e.$2), [Hand.left]);
    expect(fired.single.$1, greaterThanOrEqualTo(500));
  });

  test('right alone fires Hand.right', () {
    final fired = feed(HandSideDetector(), every(rightOnly(), 0, 1000));
    expect(fired.map((e) => e.$2), [Hand.right]);
  });

  test('fires exactly at the hold boundary, not before', () {
    expect(
      feed(HandSideDetector(), [(0, leftOnly()), (499, leftOnly())]),
      isEmpty,
    );
    expect(feed(HandSideDetector(), [(0, leftOnly()), (500, leftOnly())]), [
      (500, Hand.left),
    ]);
  });

  test('lower then raise again fires again', () {
    final d = HandSideDetector();
    final fired = feed(d, [
      ...every(leftOnly(), 0, 700),
      ...every(down(), 733, 900),
      ...every(leftOnly(), 933, 1700),
    ]);
    expect(fired.map((e) => e.$2), [Hand.left, Hand.left]);
  });

  test('both hands up never fires', () {
    expect(feed(HandSideDetector(), every(both(), 0, 1000)), isEmpty);
  });

  test('both up, right lowers, left stays: left fires 500 ms after alone', () {
    final fired = feed(HandSideDetector(), [
      ...every(both(), 0, 1000),
      ...every(leftOnly(), 1033, 2000),
    ]);
    expect(fired.map((e) => e.$2), [Hand.left]);
    // Alone since 1033; must not fire before 1533.
    expect(fired.single.$1, greaterThanOrEqualTo(1033 + 500));
  });

  test('other wrist unreliable never fires', () {
    expect(
      feed(HandSideDetector(), every(leftUpRightMissing(), 0, 2000)),
      isEmpty,
    );
    final lowConf = makePose(confidence: 0.2, leftWrist: _up, rightWrist: _dn);
    expect(feed(HandSideDetector(), every(lowConf, 0, 2000)), isEmpty);
  });

  test(
    'a single unreliable-other-wrist frame mid-hold does not fire early',
    () {
      // Left up throughout; right wrist missing at 200 only.
      final fired = feed(HandSideDetector(), [
        (0, leftOnly()),
        (200, leftUpRightMissing()),
        (400, leftOnly()),
        (499, leftOnly()),
      ]);
      expect(fired, isEmpty);
    },
  );

  test('one-frame dropout within grace neither restarts nor double fires', () {
    Pose drop() => makePose(confidence: 0.2, leftWrist: _up, rightWrist: _dn);
    final fired = feed(HandSideDetector(), [
      for (var i = 0; i < 40; i++)
        (i * 67, (i == 3 || i == 14) ? drop() : leftOnly()),
    ]);
    expect(fired, [(536, Hand.left)]);
  });

  test('a dropout longer than grace restarts the hold', () {
    Pose drop() => makePose(confidence: 0.2, leftWrist: _up, rightWrist: _dn);
    final fired = feed(HandSideDetector(), [
      ...every(leftOnly(), 0, 335, 67),
      ...every(drop(), 402, 603, 67),
      ...every(leftOnly(), 670, 1400, 67),
    ]);
    expect(fired, hasLength(1));
    expect(fired.single.$1, greaterThanOrEqualTo(670 + 500));
  });

  test('swapSides turns a left raise into Hand.right and vice versa', () {
    final l = feed(
      HandSideDetector(swapSides: true),
      every(leftOnly(), 0, 1000),
    );
    expect(l.map((e) => e.$2), [Hand.right]);
    final r = feed(
      HandSideDetector(swapSides: true),
      every(rightOnly(), 0, 1000),
    );
    expect(r.map((e) => e.$2), [Hand.left]);
  });

  test('reset re-arms and clears the hold', () {
    final d = HandSideDetector();
    expect(feed(d, every(leftOnly(), 0, 700)), hasLength(1));
    d.reset();
    expect(feed(d, every(leftOnly(), 733, 1100)), isEmpty); // hold restarted
    expect(feed(d, every(leftOnly(), 1133, 1500)), hasLength(1));
  });

  test('timing uses frame timestamps only', () {
    // Few frames, large timestamp gaps: fires on the frame at >= 500 ms.
    final fired = feed(HandSideDetector(), [
      (10000, leftOnly()),
      (10300, leftOnly()),
      (10600, leftOnly()),
    ]);
    expect(fired, [(10600, Hand.left)]);
  });
}
