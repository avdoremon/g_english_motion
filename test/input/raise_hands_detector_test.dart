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

  group('timestamp-based hold, dropout grace and confidence', () {
    // Wrists detected with low confidence (a landmark dropout).
    Pose dropout() => makePose(
      confidence: 0.2,
      leftWrist: const Offset(0.3, 0.1),
      rightWrist: const Offset(0.7, 0.1),
    );

    /// Feeds (t, pose) pairs; returns the timestamps (ms) that fired.
    List<int> feed(RaiseHandsDetector d, Iterable<(int, Pose)> frames) => [
      for (final (t, p) in frames)
        if (d.update(p, ms(t))) t,
    ];

    test('fires exactly at the 500 ms boundary, not at 499 ms', () {
      expect(feed(RaiseHandsDetector(), [(0, both()), (499, both())]), isEmpty);
      expect(
        feed(RaiseHandsDetector(), [(0, both()), (499, both()), (500, both())]),
        [500],
      );
      expect(feed(RaiseHandsDetector(), [(0, both()), (500, both())]), [500]);
    });

    test('works at 15 fps (67 ms frames): fires once after >= 500 ms', () {
      final d = RaiseHandsDetector();
      final fired = feed(d, [for (var i = 0; i < 30; i++) (i * 67, both())]);
      expect(fired, [536]); // 8 intervals x 67 ms = 536 >= 500
    });

    test(
      'a one-frame confidence dropout mid-hold does not restart the hold',
      () {
        final d = RaiseHandsDetector();
        final fired = feed(d, [
          for (var i = 0; i < 20; i++) (i * 67, i == 3 ? dropout() : both()),
        ]);
        expect(fired, [536]);
      },
    );

    test('a dropout after the fire does not re-arm (no double fire)', () {
      final d = RaiseHandsDetector();
      final fired = feed(d, [
        for (var i = 0; i < 40; i++) (i * 67, i == 12 ? dropout() : both()),
      ]);
      expect(fired, [536]);
    });

    test('a dropout longer than the grace restarts the hold and re-arms', () {
      final d = RaiseHandsDetector();
      // Hands up 0..335, doubtful 402..603 (> 150 ms), up again from 670.
      final fired = feed(d, [
        for (var t = 0; t <= 335; t += 67) (t, both()),
        for (var t = 402; t <= 603; t += 67) (t, dropout()),
        for (var t = 670; t <= 1400; t += 67) (t, both()),
      ]);
      expect(fired, hasLength(1));
      expect(fired.single, greaterThanOrEqualTo(670 + 500));
    });

    test('hands clearly lowered reset immediately (no grace)', () {
      final d = RaiseHandsDetector();
      final fired = feed(d, [
        (0, both()),
        (200, both()),
        (267, down()),
        (333, both()),
        (700, both()), // only 367 ms since restart
      ]);
      expect(fired, isEmpty);
    });

    test('minConfidence is configurable', () {
      Pose conf(double c) => makePose(
        confidence: c,
        leftWrist: const Offset(0.3, 0.1),
        rightWrist: const Offset(0.7, 0.1),
      );
      final frames = [(0, conf(0.6)), (600, conf(0.6))];
      expect(feed(RaiseHandsDetector(minConfidence: 0.7), frames), isEmpty);
      expect(feed(RaiseHandsDetector(minConfidence: 0.5), frames), [600]);
      expect(feed(RaiseHandsDetector(), frames), [600]);
    });
  });
}
