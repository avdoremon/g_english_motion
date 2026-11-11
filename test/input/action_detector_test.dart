import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/action_detector.dart';
import 'package:g_english_motion/input/calibrator.dart';
import 'package:g_english_motion/input/pose_types.dart';

import '../helpers/synthetic_poses.dart';

Duration ms(int v) => Duration(milliseconds: v);

const cal = Calibration(
  torsoHeight: 0.3,
  centerX: 0.5,
  baselineHipY: 0.6,
  baselineShoulderY: 0.3,
);

Pose stand() => makePose(
  leftWrist: const Offset(0.4, 0.55),
  rightWrist: const Offset(0.6, 0.55),
);

/// Hands above the nose (nose y = hipY - 0.4), body lifted by [lift].
Pose handsUp({double lift = 0}) => makePose(
  hipY: 0.6 - lift,
  leftWrist: Offset(0.3, 0.1 - lift),
  rightWrist: Offset(0.7, 0.1 - lift),
);

/// Feeds standing frames to settle the detectors, 0..[until] ms.
ActionDetector settled() {
  final d = ActionDetector(cal);
  for (var t = 0; t <= 1200; t += 33) {
    d.update(stand(), ms(t));
  }
  return d;
}

/// Feeds [pose] every 33 ms and returns how often each action fired.
Map<PuppyAction, int> run(ActionDetector d, Pose pose, int from, int to) {
  final counts = {for (final a in PuppyAction.values) a: 0};
  for (var t = from; t <= to; t += 33) {
    for (final a in d.update(pose, ms(t))) {
      counts[a] = counts[a]! + 1;
    }
  }
  return counts;
}

void expectOnly(Map<PuppyAction, int> c, PuppyAction a) {
  for (final e in c.entries) {
    expect(e.value, e.key == a ? 1 : 0, reason: '${e.key}');
  }
}

void main() {
  test('standing still yields nothing', () {
    final d = settled();
    final c = run(d, stand(), 1300, 4000);
    expect(c.values.every((v) => v == 0), isTrue);
  });

  test('hands up alone yields exactly handsUp', () {
    final d = settled();
    expectOnly(run(d, handsUp(), 1300, 2500), PuppyAction.handsUp);
  });

  test('squat alone yields exactly squat', () {
    final d = settled();
    final squat = makePose(hipY: 0.7, kneeY: 0.75);
    expectOnly(run(d, squat, 1300, 2500), PuppyAction.squat);
  });

  test('clap alone yields exactly clap', () {
    final d = settled();
    final apart = makePose(
      leftWrist: const Offset(0.3, 0.4),
      rightWrist: const Offset(0.7, 0.4),
    );
    final together = makePose(
      leftWrist: const Offset(0.49, 0.4),
      rightWrist: const Offset(0.51, 0.4),
    );
    final c = run(d, apart, 1300, 1500);
    final c2 = run(d, together, 1533, 1800);
    c2.updateAll((k, v) => v + c[k]!);
    expectOnly(c2, PuppyAction.clap);
  });

  test('jump alone yields exactly jump', () {
    final d = settled();
    final up = makePose(
      hipY: 0.5,
      leftWrist: const Offset(0.4, 0.45),
      rightWrist: const Offset(0.6, 0.45),
    );
    final c = run(d, up, 1300, 1500);
    expectOnly(c, PuppyAction.jump);
  });

  test('jump with hands up yields both jump and handsUp', () {
    final d = settled();
    final c = run(d, handsUp(lift: 0.1), 1300, 2400);
    expect(c[PuppyAction.jump], 1);
    expect(c[PuppyAction.handsUp], 1);
    expect(c[PuppyAction.clap], 0);
    expect(c[PuppyAction.squat], 0);
  });

  test('held hands-up across a long dropout fires once', () {
    final d = settled();
    var c = run(d, handsUp(), 1300, 2200);
    expect(c[PuppyAction.handsUp], 1);
    // 2 s of unreliable frames.
    for (var t = 2233; t < 4300; t += 33) {
      expect(d.update(Pose({}), ms(t)), isEmpty);
    }
    c = run(d, handsUp(), 4300, 6000);
    expect(c[PuppyAction.handsUp], 0);
    // Lowering the hands reliably re-arms.
    run(d, stand(), 6033, 6300);
    c = run(d, handsUp(), 6333, 7200);
    expect(c[PuppyAction.handsUp], 1);
  });

  test('suppressUntil blocks all four', () {
    final d = settled();
    d.suppressUntil(ms(5000));
    var c = run(d, handsUp(lift: 0.1), 1300, 2400);
    expect(c.values.every((v) => v == 0), isTrue);
    d.reset();
    d.suppressUntil(ms(5000));
    final squat = makePose(hipY: 0.7, kneeY: 0.75);
    c = run(d, squat, 2500, 3500);
    expect(c.values.every((v) => v == 0), isTrue);
    final apart = makePose(
      leftWrist: const Offset(0.3, 0.4),
      rightWrist: const Offset(0.7, 0.4),
    );
    final together = makePose(
      leftWrist: const Offset(0.49, 0.4),
      rightWrist: const Offset(0.51, 0.4),
    );
    run(d, apart, 3600, 3800);
    c = run(d, together, 3833, 4200);
    expect(c.values.every((v) => v == 0), isTrue);
  });

  test('rebaseline passes through to the jump detector', () {
    final d = ActionDetector(cal);
    // Body now rests 0.15 higher than calibrated: without a rebaseline it
    // would read as a jump.
    d.rebaseline(makePose(hipY: 0.45));
    final c = run(d, makePose(hipY: 0.45), 0, 300);
    expect(c[PuppyAction.jump], 0);
  });

  test('rebaseline also rebases the squat baseline', () {
    final d = ActionDetector(cal);
    // Player stands 0.1 lower than calibrated (0.333 torso: reads as squat).
    final low = makePose(hipY: 0.7, kneeY: 0.95);
    d.rebaseline(low);
    var c = run(d, low, 0, 1500);
    expect(c.values.every((v) => v == 0), isTrue);
    // A real drop from the new rest fires squat.
    c = run(d, makePose(hipY: 0.8, kneeY: 0.95), 1533, 2300);
    expect(c[PuppyAction.squat], 1);
    // And a player standing higher than calibrated: no squat, drop fires.
    final e = ActionDetector(cal);
    final high = makePose(hipY: 0.5);
    e.rebaseline(high);
    expect(run(e, high, 0, 1500)[PuppyAction.squat], 0);
    expect(run(e, makePose(hipY: 0.6), 1533, 2300)[PuppyAction.squat], 1);
  });

  test('jump and handsUp can land on the same frame', () {
    final d = settled();
    // Hands up at rest for 480 ms, then the body lifts on the frame that
    // completes the 500 ms hold.
    final rest = handsUp();
    var t = 1300;
    for (; t < 1300 + 480; t += 30) {
      expect(d.update(rest, ms(t)), isEmpty);
    }
    final both = d.update(handsUp(lift: 0.1), ms(1800));
    expect(both, {PuppyAction.jump, PuppyAction.handsUp});
  });

  test('standing up from a held squat does not fire jump', () {
    final d = settled();
    final squat = makePose(hipY: 0.7, kneeY: 0.75);
    expectOnly(run(d, squat, 1300, 3800), PuppyAction.squat);
    final c = run(d, stand(), 3833, 4600);
    expect(c.values.every((v) => v == 0), isTrue, reason: '$c');
  });

  group('rearm', () {
    test('a hands-up held across rearm registers once more', () {
      final d = settled();
      expectOnly(run(d, handsUp(), 1300, 2400), PuppyAction.handsUp);
      expect(run(d, handsUp(), 2433, 3300)[PuppyAction.handsUp], 0);
      d.rearm();
      final c = run(d, handsUp(), 3333, 4300);
      expect(c[PuppyAction.handsUp], 1);
      expect(c[PuppyAction.jump], 0);
    });

    test('a squat held across rearm registers once more', () {
      final d = settled();
      final squat = makePose(hipY: 0.7, kneeY: 0.75);
      expectOnly(run(d, squat, 1300, 2500), PuppyAction.squat);
      expect(run(d, squat, 2533, 3000)[PuppyAction.squat], 0);
      d.rearm();
      expect(run(d, squat, 3033, 3800)[PuppyAction.squat], 1);
    });

    test('rearm on a standing child yields nothing; jump stays an edge', () {
      final d = settled();
      d.rearm();
      expect(run(d, stand(), 1300, 3000).values.every((v) => v == 0), isTrue);
      // A lifted pose held through rearm is not a fresh jump...
      final up = makePose(
        hipY: 0.5,
        leftWrist: const Offset(0.4, 0.45),
        rightWrist: const Offset(0.6, 0.45),
      );
      expectOnly(run(d, up, 3033, 3200), PuppyAction.jump);
      d.rearm();
      expect(run(d, up, 3233, 3800)[PuppyAction.jump], 0);
      // ...but a real jump after rearm still fires.
      run(d, stand(), 3833, 5200);
      expect(run(d, up, 5233, 5400)[PuppyAction.jump], 1);
    });
  });
}
