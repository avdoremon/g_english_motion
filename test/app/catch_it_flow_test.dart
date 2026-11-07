import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/levels/scoring.dart';
import 'package:g_english_motion/modes/catch_it.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/session/level_session.dart';

import '../helpers/game_harness.dart';

void main() {
  late GameHarness h;

  Future<void> setUpCatchIt({int seed = 7}) async {
    // hangTts: the question stays "being read" until the ~12 s prompt timeout.
    h = await GameHarness.create(
      modes: const [ModeKind.catchIt],
      mode: ModeKind.catchIt,
      withImages: true,
      hangTts: true,
      seed: seed,
    );
    await h.startAndCalibrate();
  }

  tearDown(() => h.dispose());

  int correct(GameHarness h) =>
      (h.controller.session!.current.question as ChoiceQuestion).correctIndex;

  test('controller builds a CatchItRound with the scored time limit', () async {
    await setUpCatchIt();
    final s = h.controller.session!;
    expect(s.current.mode, ModeKind.catchIt);
    final r = s.round;
    expect(r, isA<CatchItRound>());
    expect(r.timeLimit, Scoring.timeFor(h.controller.level, ModeKind.catchIt));
    expect((r as CatchItRound).lane, 1); // calibrated in the middle lane
  });

  test(
    'lane changed while the question is read counts at the catch line',
    () async {
      // A seed whose correct lane differs from the starting (middle) lane, so
      // a stale round lane would be graded wrong.
      var seed = 1;
      while (true) {
        await setUpCatchIt(seed: seed);
        if (correct(h) != 1) break;
        await h.dispose();
        seed++;
      }
      final s = h.controller.session!;
      expect(s.phase, SessionPhase.prompting);
      h.controller.debugInject(LaneChanged(correct(h), at: Duration.zero));
      await h.run(const Duration(seconds: 13)); // prompt ends
      expect(s.phase, SessionPhase.playing);
      await h.run(const Duration(seconds: 21)); // pictures reach the catch line
      expect(s.lastResult, RoundResult.correct);
    },
  );

  test('wrong lane chosen while the question is read grades wrong', () async {
    var seed = 1;
    while (true) {
      await setUpCatchIt(seed: seed);
      if (correct(h) == 1) break;
      await h.dispose();
      seed++;
    }
    final s = h.controller.session!;
    // The stale (middle) lane would be correct; the child moved away.
    h.controller.debugInject(LaneChanged(0, at: Duration.zero));
    await h.run(const Duration(seconds: 13));
    await h.run(const Duration(seconds: 21));
    expect(s.lastResult, RoundResult.wrong);
  });

  test('child gone while the question is read: the round waits', () async {
    await setUpCatchIt();
    final s = h.controller.session!;
    final r = s.round as CatchItRound;
    expect(s.phase, SessionPhase.prompting);
    h.controller.debugInject(PlayerLost(at: h.lastFrameAt));
    s.onPromptFinished();
    expect(s.phase, SessionPhase.playing);
    // Well past the time limit with nobody there (ticks only).
    await h.run(r.timeLimit * 2, withFrames: false);
    expect(s.lastResult, isNull);
    expect(s.round, same(r));
    expect(r.result, isNull);
    expect(r.fallFraction, 0);
    // The child comes back: the clock resumes.
    h.controller.debugInject(PlayerFound(at: h.lastFrameAt));
    await h.run(const Duration(seconds: 2));
    expect(r.fallFraction, greaterThan(0));
  });
}
