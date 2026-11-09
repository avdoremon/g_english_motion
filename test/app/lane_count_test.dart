import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/levels/level_config.dart';
import 'package:g_english_motion/modes/catch_it.dart';
import 'package:g_english_motion/modes/lane_jump.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/session/level_session.dart';

import '../helpers/game_harness.dart';
import '../helpers/synthetic_poses.dart';

/// Levels 3-5 have `choiceCount` 4, but catchIt always shows 3 lanes.
const _level4 = LevelConfig(
  level: 3,
  questionCount: 8,
  baseTime: Duration(seconds: 20),
  choiceCount: 4,
  hints: HintMode.full,
  window: UnitWindow.current,
);

/// Hip x of a player standing 0.3 lane-widths right of the screen centre:
/// the centre lane of 3 lanes, but lane 2 of 4. (Not the far lane, where a
/// wrong count would be hidden by clamping.)
double _nearCentre() {
  final w = GameHarness.hipXForLane(0, 3) - GameHarness.hipXForLane(1, 3);
  return GameHarness.hipXForLane(1, 3) - 0.3 * w;
}

void main() {
  late GameHarness h;
  tearDown(() => h.dispose());

  test('catchIt at choiceCount 4 tracks the player over 3 lanes', () async {
    h = await GameHarness.create(
      level: _level4,
      modes: const [ModeKind.catchIt],
      mode: ModeKind.catchIt,
      grade: 2,
      withImages: true,
      hangTts: true,
    );
    await h.startAndCalibrate();
    final s = h.controller.session!;
    expect(s.round, isA<CatchItRound>());
    await h.run(
      const Duration(seconds: 1),
      pose: (_) => makePose(hipX: _nearCentre()),
    );
    expect((s.round as CatchItRound).lane, 1);
    expect(h.controller.selectedLane, 1);
  });

  test('laneJump(4) and catchIt(3) alternate with cursor on', () async {
    h = await GameHarness.create(
      level: _level4,
      grade: 2,
      shuffle: true,
      withImages: true,
      modes: const [ModeKind.laneJump, ModeKind.catchIt, ModeKind.memoryFlip],
    );
    await h.startAndCalibrate();
    final s = h.controller.session!;
    final x = _nearCentre();
    final seen = <ModeKind, Set<int>>{};
    Round? last;
    for (var i = 0; i < 600 && s.phase != SessionPhase.finished; i++) {
      await h.run(
        const Duration(milliseconds: 500),
        pose: (_) => makePose(hipX: x),
      );
      final r = s.round;
      if (s.phase != SessionPhase.playing || identical(r, last)) continue;
      if (r is LaneJumpRound) {
        last = r;
        seen.putIfAbsent(ModeKind.laneJump, () => {}).add(r.selectedLane);
      } else if (r is CatchItRound) {
        last = r;
        seen.putIfAbsent(ModeKind.catchIt, () => {}).add(r.lane);
      }
    }
    expect(seen[ModeKind.laneJump], {2}); // 4 lanes
    expect(seen[ModeKind.catchIt], {1}); // 3 lanes
  });
}
