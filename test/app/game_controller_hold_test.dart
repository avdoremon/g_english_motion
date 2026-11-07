import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/modes/hold_pick.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/session/level_session.dart';

import '../helpers/game_harness.dart';

void main() {
  for (final mode in [ModeKind.memoryFlip, ModeKind.balloonPop]) {
    group('$mode', () {
      late GameHarness h;

      setUp(() async {
        h = await GameHarness.create(
          grade: mode == ModeKind.memoryFlip ? 2 : 3,
          words: const ['cat', 'cap', 'cut', 'cot', 'car', 'bat', 'bag', 'big'],
          modes: [mode],
          mode: mode,
          withImages: true,
          hangTts: true,
        );
        await h.startAndCalibrate();
        // The question was read: play starts.
        h.controller.session!.onPromptFinished();
      });
      tearDown(() => h.dispose());

      /// Centre of the default layout cell of choice [i].
      Offset centre(HoldPickRound r, int i) => r.targetRect(i).center;

      test('is a HoldPickRound with the mode timings', () {
        final r = h.controller.session!.round;
        expect(r, isA<HoldPickRound>());
        expect(
          (r as HoldPickRound).peek,
          mode == ModeKind.memoryFlip
              ? const Duration(seconds: 2)
              : Duration.zero,
        );
      });

      test('a hold by injected CursorMoved events grades the round', () {
        final s = h.controller.session!;
        final r = s.round as HoldPickRound;
        r.tick(const Duration(seconds: 3)); // end any peek
        final c = centre(r, r.question.correctIndex);
        var t = h.lastFrameAt;
        for (var i = 0; i <= 50; i++) {
          h.controller.debugInject(
            CursorMoved(c.dx, c.dy, at: t + Duration(milliseconds: 50 * i)),
          );
        }
        expect(s.phase, SessionPhase.feedback);
        expect(s.lastResult, RoundResult.correct);
      });

      test('holdTarget(choice:i) taps an answer', () {
        final s = h.controller.session!;
        final r = s.round as HoldPickRound;
        r.tick(const Duration(seconds: 3));
        h.controller.holdTarget('choice:${r.question.correctIndex}');
        expect(s.phase, SessionPhase.feedback);
        expect(s.lastResult, RoundResult.correct);
      });
    });
  }
}
