import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/audio/voice_lines.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/modes/drag_spell.dart';
import 'package:g_english_motion/modes/sky_shoot.dart';
import 'package:g_english_motion/session/level_session.dart';

import '../helpers/game_harness.dart';
import '../helpers/synthetic_poses.dart';

Duration ms(int v) => Duration(milliseconds: v);

void main() {
  test(
    'grade 3 mixes DragSpell and SkyShoot questions, one round each',
    () async {
      final h = await GameHarness.create(
        grade: 3,
        modes: const [ModeKind.dragSpell, ModeKind.skyShoot],
      );
      await h.startAndCalibrate();
      final s = h.controller.session!;
      expect(s.plan.map((p) => p.mode).toSet(), {
        ModeKind.dragSpell,
        ModeKind.skyShoot,
      });
      for (final pq in s.plan) {
        switch (pq.mode) {
          case ModeKind.dragSpell:
            expect(
              pq.question,
              anyOf(isA<SpellQuestion>(), isA<OrderQuestion>()),
            );
          case ModeKind.skyShoot:
            expect(pq.question, isA<ChoiceQuestion>());
          default:
            fail('unexpected mode ${pq.mode}');
        }
      }
      expect(
        s.round,
        s.current.mode == ModeKind.skyShoot
            ? isA<SkyShootRound>()
            : isA<DragSpellRound>(),
      );
      await h.dispose();
    },
  );

  group('SkyShoot through the pose pipeline', () {
    late GameHarness h;

    setUp(() async {
      h = await GameHarness.create(grade: 3, modes: const [ModeKind.skyShoot]);
      await h.startAndCalibrate();
      // Past the 500 ms grace after the question starts.
      await h.run(const Duration(milliseconds: 1200));
    });

    tearDown(() => h.dispose());

    SkyShootRound round() => h.controller.session!.round as SkyShootRound;

    test(
      'a jump becomes a shot scored at (event time - castLatency)',
      () async {
        final r = round();
        final q = r.question;
        final confirmed = <Confirmed>[];
        h.controller.events.listen((e) {
          if (e is Confirmed) confirmed.add(e);
        });
        await h.jump();
        await h.run(const Duration(milliseconds: 100));
        expect(confirmed, hasLength(1));
        final t = confirmed.single.at - h.controller.castLatency;
        final x = r.field.arrowX(t);
        final shouldHit = [
          for (var i = 0; i < q.choices.length; i++)
            (r.field.answerX(i, t) - x).abs() <= r.hitRadius,
        ].any((b) => b);
        expect(r.phase == SkyPhase.reeling, shouldHit);
        expect(r.shotsLeft, shouldHit ? 3 : 2);
      },
    );

    test('hitting an answer says "pull the rope" and alternating wrist '
        'beats reel it in', () async {
      final r = round();
      // A hit regardless of where the arrow is: event time chosen on the
      // field's clock.
      Duration? at;
      for (var ms = 0; ms < 60000 && at == null; ms += 10) {
        final t = h.controller.frameClock + Duration(milliseconds: ms);
        final x = r.field.arrowX(t);
        if ((r.field.answerX(0, t) - x).abs() < 0.04) {
          at = t + h.controller.castLatency;
        }
      }
      h.controller.touchInput(Confirmed(0, at: at!));
      expect(r.phase, SkyPhase.reeling);
      await pumpEventQueue(times: 10);
      expect(h.captions, contains(VoiceLine.pullTheRope.caption));

      double beat(Duration t, int start) {
        final s = t.inMilliseconds - start;
        if (s < 0 || s >= 600) return 0.3;
        return s < 300
            ? 0.3 + 0.15 * s / 300
            : 0.3 + 0.15 * (1 - (s - 300) / 300);
      }

      // left at 0, right at 800, left at 1600, right at 2400 (ms since start)
      await h.run(
        const Duration(milliseconds: 3400),
        pose: (since) => makePose(
          hipX: GameHarness.hipXForLane(1, 3),
          leftWrist: Offset(
            0.4,
            beat(since, 100) < 0.31 ? beat(since, 1700) : beat(since, 100),
          ),
          rightWrist: Offset(
            0.6,
            beat(since, 900) < 0.31 ? beat(since, 2500) : beat(since, 900),
          ),
        ),
        stopWhen: () => r.result != null,
      );
      expect(r.pulls, 4);
      expect(r.result, isNotNull);
      expect(h.controller.session!.phase, SessionPhase.feedback);
    });

    test(
      'the clock stands still while the answer is being pulled in',
      () async {
        final r = round();
        Duration? at;
        for (var ms = 0; ms < 60000 && at == null; ms += 10) {
          final t = h.controller.frameClock + Duration(milliseconds: ms);
          if ((r.field.answerX(1, t) - r.field.arrowX(t)).abs() < 0.04) {
            at = t + h.controller.castLatency;
          }
        }
        h.controller.touchInput(Confirmed(0, at: at!));
        final left = r.remaining;
        await h.run(const Duration(seconds: 5));
        expect(r.remaining, left);
        expect(r.result, isNull);
      },
    );

    test('the spoken word is not captioned before the answer', () {
      expect(
        h.controller.shouldShowCaption(round().question.ttsText),
        round().question.form == QuestionForm.listenPickWord ? isFalse : isTrue,
      );
    });
  });
}
