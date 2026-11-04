import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/app/game_controller.dart';
import 'package:g_english_motion/content/content_repository.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/levels/level_config.dart';
import 'package:g_english_motion/modes/drag_spell.dart';
import 'package:g_english_motion/modes/sky_shoot.dart';

import '../helpers/game_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('grade 3 level 1 on the shipped content starts a DragSpell/SkyShoot '
      'mix through the GameController (fake pose source)', () async {
    final repo = await ContentRepository.loadFromAssets(rootBundle);
    final level = (await LevelConfig.load(rootBundle))
        .firstWhere((l) => l.level == 1);
    final h = await GameHarness.create(grade: 3, level: level, repo: repo);
    await h.startAndCalibrate();

    expect(h.controller.phase, GamePhase.playing);
    final s = h.controller.session!;
    expect(s.plan, hasLength(level.questionCount));
    expect(s.plan.map((p) => p.mode).toSet(), {
      ModeKind.dragSpell,
      ModeKind.skyShoot,
    });
    // Level 1 stays inside unit 1 of grade 3.
    for (final p in s.plan) {
      expect(p.question.itemId, startsWith('g3u01-'));
    }
    expect(
      s.round,
      s.current.mode == ModeKind.skyShoot
          ? isA<SkyShootRound>()
          : isA<DragSpellRound>(),
    );
    await h.dispose();
  });
}
