
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/clap_detector.dart';
import 'package:g_english_motion/input/pose_types.dart';

import '../helpers/synthetic_poses.dart';

Duration ms(int v) => Duration(milliseconds: v);

// Defaults: shoulders at x 0.42/0.58 (width 0.16), hips y 0.6, chest y 0.3.
Pose wrists(double lx, double rx, {double ly = 0.4, double ry = 0.4}) =>
    makePose(leftWrist: Offset(lx, ly), rightWrist: Offset(rx, ry));
Pose apart() => wrists(0.3, 0.7);
Pose together() => wrists(0.49, 0.51);

void main() {
  test('apart then together within the window fires once', () {
    final d = ClapDetector();
    expect(d.update(apart(), ms(0)), isFalse);
    expect(d.update(apart(), ms(100)), isFalse);
    expect(d.update(together(), ms(300)), isTrue);
    expect(d.update(together(), ms(333)), isFalse);
  });

  test('a slow approach (longer than the window) never fires', () {
    final d = ClapDetector();
    expect(d.update(apart(), ms(0)), isFalse);
    expect(d.update(wrists(0.45, 0.55), ms(500)), isFalse);
    expect(d.update(together(), ms(1000)), isFalse);
    expect(d.update(together(), ms(1100)), isFalse);
  });

  test('wrists below the hips never fire', () {
    final d = ClapDetector();
    d.update(apart(), ms(0));
    expect(d.update(wrists(0.49, 0.51, ly: 0.8, ry: 0.8), ms(200)), isFalse);
  });

  test('wrists at different heights do not clap', () {
    final d = ClapDetector();
    d.update(apart(), ms(0));
    expect(d.update(wrists(0.49, 0.51, ly: 0.2, ry: 0.5), ms(200)), isFalse);
  });

  test('a held clap does not re-fire until apart again', () {
    final d = ClapDetector(debounce: Duration.zero);
    d.update(apart(), ms(0));
    expect(d.update(together(), ms(200)), isTrue);
    for (var t = 233; t < 3000; t += 33) {
      expect(d.update(together(), ms(t)), isFalse);
    }
    d.update(apart(), ms(3100));
    expect(d.update(together(), ms(3300)), isTrue);
  });

  test('debounce blocks a second clap too soon', () {
    final d = ClapDetector();
    d.update(apart(), ms(0));
    expect(d.update(together(), ms(200)), isTrue);
    d.update(apart(), ms(300));
    expect(d.update(together(), ms(500)), isFalse);
    d.update(apart(), ms(600));
    expect(d.update(together(), ms(1100)), isTrue);
  });

  test('a doubtful frame never fires', () {
    final d = ClapDetector();
    d.update(apart(), ms(0));
    final missing = makePose(leftWrist: const Offset(0.49, 0.4));
    expect(d.update(missing, ms(100)), isFalse);
    final lowConf = Pose({
      ...together().joints,
      PoseJoint.rightWrist: const Landmark(0.51, 0.4, 0.1),
    });
    expect(d.update(lowConf, ms(200)), isFalse);
  });

  test('reset forgets the apart state', () {
    final d = ClapDetector();
    d.update(apart(), ms(0));
    d.reset();
    expect(d.update(together(), ms(100)), isFalse);
  });
}
