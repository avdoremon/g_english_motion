import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/modes/mode_availability.dart';

import '../helpers/game_harness.dart';

void main() {
  test('modesForGrade(1) has catchIt and laneJump, not balloonPop', () {
    final m = modesForGrade(1);
    expect(m, containsAll([ModeKind.catchIt, ModeKind.laneJump]));
    expect(m, isNot(contains(ModeKind.balloonPop)));
  });

  test('modesForGrade(3) has the upper modes, not catchIt', () {
    final m = modesForGrade(3);
    expect(
      m,
      containsAll([
        ModeKind.balloonPop,
        ModeKind.memoryFlip,
        ModeKind.dragSpell,
        ModeKind.skyShoot,
      ]),
    );
    expect(m, isNot(contains(ModeKind.catchIt)));
  });

  test('sayIt is listed for grades 1-5 but never a default', () {
    final info = kModeInfos.firstWhere((i) => i.mode == ModeKind.sayIt);
    expect((info.minGrade, info.maxGrade), (1, 5));
    for (var g = 1; g <= 5; g++) {
      expect(defaultModesForGrade(g), isNot(contains(ModeKind.sayIt)));
    }
  });

  test('defaults keep today\'s mix', () {
    expect(defaultModesForGrade(1), {ModeKind.laneJump});
    expect(defaultModesForGrade(2), {ModeKind.laneJump});
    expect(defaultModesForGrade(3), {ModeKind.dragSpell, ModeKind.skyShoot});
    expect(defaultModesForGrade(4), {ModeKind.dragSpell, ModeKind.skyShoot});
    expect(defaultModesForGrade(5), {ModeKind.dragSpell, ModeKind.skyShoot});
  });

  test('ContentItem.fromJson accepts the new mode names', () {
    final it = ContentItem.fromJson({
      'id': 'a',
      'word': 'a',
      'ttsText': 'a',
      'modes': ['catchIt', 'memoryFlip', 'balloonPop'],
    });
    expect(it.modes, [
      ModeKind.catchIt,
      ModeKind.memoryFlip,
      ModeKind.balloonPop,
    ]);
  });

  test('GameController ignores a mode not valid for the grade', () async {
    final h = await GameHarness.create(
      grade: 4,
      modes: const [ModeKind.dragSpell, ModeKind.skyShoot],
      mode: ModeKind.catchIt,
    );
    expect(h.controller.activeModes, defaultModesForGrade(4));
  });

  test('GameController uses a valid chosen mode', () async {
    final h = await GameHarness.create(
      grade: 4,
      modes: const [ModeKind.dragSpell],
      mode: ModeKind.dragSpell,
    );
    expect(h.controller.activeModes, {ModeKind.dragSpell});
  });
}
