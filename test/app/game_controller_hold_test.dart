import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/input/pose_types.dart';
import 'package:g_english_motion/modes/hold_pick.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/session/level_session.dart';

import '../helpers/game_harness.dart';
import '../helpers/synthetic_poses.dart';

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

  group('hold layout seam', () {
    late GameHarness h;
    setUp(() async {
      h = await GameHarness.create(
        grade: 3,
        words: const ['cat', 'cap', 'cut', 'cot', 'car', 'bat', 'bag', 'big'],
        modes: const [ModeKind.balloonPop],
        mode: ModeKind.balloonPop,
        withImages: true,
        hangTts: true,
      );
      await h.startAndCalibrate();
      h.controller.session!.onPromptFinished();
    });
    tearDown(() => h.dispose());

    HoldPickRound round() => h.controller.session!.round as HoldPickRound;

    void hold(Offset c, {int ms = 800}) {
      var t = h.lastFrameAt;
      for (var i = 0; i <= ms ~/ 50; i++) {
        h.controller.debugInject(
          CursorMoved(c.dx, c.dy, at: t + Duration(milliseconds: 50 * i)),
        );
      }
    }

    test(
      'the default grid has gaps: a resting hand between cells picks none',
      () {
        final r = round();
        for (var i = 0; i + 1 < r.question.choices.length; i++) {
          final a = r.targetRect(i);
          final b = r.targetRect(i + 1);
          if (a.center.dy != b.center.dy) continue;
          final gap = Offset((a.right + b.left) / 2, a.center.dy);
          hold(gap);
          expect(r.hoverTarget, isNull);
        }
        hold(const Offset(0.001, 0.001)); // the margin
        expect(r.hoverTarget, isNull);
        expect(h.controller.session!.phase, SessionPhase.playing);
      },
    );

    test('setHoldLayout takes effect mid-round', () {
      final r = round();
      final n = r.question.choices.length;
      final old = r.targetRect(0).center;
      h.controller.setHoldLayout(
        (i) => Rect.fromLTWH(0.05 + 0.3 * i, 0.75, 0.2, 0.2),
      );
      hold(old, ms: 100);
      expect(r.hoverTarget, isNull, reason: 'old position is empty now');
      hold(r.targetRect(n - 1).center, ms: 100);
      expect(r.hoverTarget, 'choice:${n - 1}');
      h.controller.clearHoldLayout();
      hold(old, ms: 100);
      expect(r.hoverTarget, 'choice:0');
    });
  });

  test(
    'player lost during the prompt: the round starts without a clock',
    () async {
      final h = await GameHarness.create(
        grade: 2,
        words: const ['cat', 'cap', 'cut', 'cot', 'car', 'bat', 'bag', 'big'],
        modes: const [ModeKind.memoryFlip],
        mode: ModeKind.memoryFlip,
        withImages: true,
        hangTts: true,
      );
      addTearDown(h.dispose);
      await h.startAndCalibrate();
      final s = h.controller.session!;
      expect(s.phase, SessionPhase.prompting);
      h.controller.debugInject(PlayerLost(at: h.lastFrameAt));
      // No frames: the prompt watchdog starts the round after 12 s.
      await h.run(const Duration(seconds: 13), withFrames: false);
      expect(s.phase, SessionPhase.playing);
      final r = s.round as HoldPickRound;
      final before = r.remaining;
      await h.run(const Duration(seconds: 4), withFrames: false);
      expect(
        r.peeking,
        isTrue,
        reason: 'the peek does not run with nobody there',
      );
      expect(r.remaining, before);
      expect(r.clockRunning, isFalse);
    },
  );

  test(
    'memoryFlip / balloonPop captions would leak the answer: hidden',
    () async {
      final h = await GameHarness.create(
        grade: 2,
        words: const ['cat', 'cap', 'cut', 'cot', 'car', 'bat', 'bag', 'big'],
        modes: const [ModeKind.memoryFlip],
        mode: ModeKind.memoryFlip,
        withImages: true,
        hangTts: true,
      );
      addTearDown(h.dispose);
      await h.startAndCalibrate();
      expect(h.controller.shouldShowCaption('cat'), isFalse);
    },
  );

  group('hand cursor by mode', () {
    Future<(GameHarness, List<CursorMoved>)> start(
      int grade,
      ModeKind mode,
    ) async {
      final h = await GameHarness.create(
        grade: grade,
        words: const ['cat', 'cap', 'cut', 'cot', 'car', 'bat', 'bag', 'big'],
        modes: [mode],
        mode: mode,
        withImages: true,
      );
      addTearDown(h.dispose);
      final seen = <CursorMoved>[];
      h.controller.events.listen((e) {
        if (e is CursorMoved) seen.add(e);
      });
      await h.startAndCalibrate();
      return (h, seen);
    }

    Pose raisedHand(GameHarness h) {
      final x = GameHarness.hipXForLane(h.lane, h.controller.level.choiceCount);
      return makePose(hipX: x, rightWrist: Offset(x, 0.4));
    }

    test(
      'grade 2 memoryFlip gets CursorMoved and a hold grades the round',
      () async {
        final (h, seen) = await start(2, ModeKind.memoryFlip);
        final s = h.controller.session!;
        final r = s.round as HoldPickRound;
        final good = r.question.correctIndex;
        // The whole board is the right card; the others are empty.
        h.controller.setHoldLayout(
          (i) => i == good ? const Rect.fromLTRB(0, 0, 1, 1) : Rect.zero,
        );
        await h.run(
          const Duration(milliseconds: 2500),
          pose: (_) => raisedHand(h),
        );
        expect(seen, isNotEmpty);
        expect(r.peeking, isFalse);
        await h.run(
          const Duration(seconds: 2),
          pose: (_) => raisedHand(h),
          stopWhen: () => s.phase == SessionPhase.feedback,
        );
        expect(s.phase, SessionPhase.feedback);
        expect(s.lastResult, RoundResult.correct);
      },
    );

    test('grade 1 and 2 laneJump sessions have no cursor', () async {
      for (final g in [1, 2]) {
        final (h, seen) = await start(g, ModeKind.laneJump);
        await h.run(const Duration(seconds: 1), pose: (_) => raisedHand(h));
        expect(seen, isEmpty, reason: 'grade $g');
        expect(h.controller.session!.round, isNot(isA<HoldPickRound>()));
      }
    });
  });
}
