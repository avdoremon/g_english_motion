import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/audio/voice_lines.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/input/pose_types.dart';
import 'package:g_english_motion/levels/level_config.dart';
import 'package:g_english_motion/levels/scoring.dart';
import 'package:g_english_motion/modes/catch_it.dart';
import 'package:g_english_motion/modes/lane_jump.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/modes/yes_no.dart';
import 'package:g_english_motion/session/level_session.dart';

import '../helpers/game_harness.dart';
import '../helpers/synthetic_poses.dart';

const _level4 = LevelConfig(
  level: 3,
  questionCount: 8,
  baseTime: Duration(seconds: 20),
  choiceCount: 4,
  hints: HintMode.full,
  window: UnitWindow.current,
);

void main() {
  late GameHarness h;

  Future<void> setUpYesNo({
    int seed = 7,
    bool hangTts = true,
    bool Function(ChoiceQuestion q)? want,
  }) async {
    var s = seed;
    while (true) {
      h = await GameHarness.create(
        modes: const [ModeKind.yesNo],
        mode: ModeKind.yesNo,
        withImages: true,
        hangTts: hangTts,
        seed: s,
      );
      await h.startAndCalibrate();
      final q = h.controller.session!.current.question as ChoiceQuestion;
      if (want == null || want(q)) return;
      await h.dispose();
      s++;
    }
  }

  tearDown(() => h.dispose());

  ChoiceQuestion q0() =>
      h.controller.session!.current.question as ChoiceQuestion;

  void endPrompt() => h.controller.session!.onPromptFinished();

  test('controller builds a YesNoRound for the statement', () async {
    await setUpYesNo();
    final s = h.controller.session!;
    expect(s.current.mode, ModeKind.yesNo);
    expect(s.round, isA<YesNoRound>());
    expect(
      s.round.timeLimit,
      Scoring.timeFor(h.controller.level, ModeKind.yesNo),
    );
    expect(q0().form, QuestionForm.trueFalse);
  });

  test('the prompt speaks the statement, nothing about its truth', () async {
    await setUpYesNo(hangTts: false);
    final q = q0();
    expect(h.ttsLog, contains('tts:${q.ttsText}'));
    expect(h.ttsLog.where((l) => l.contains('Đáp án')), isEmpty);
  });

  test('a left hand answers Đúng (choice 0) while playing', () async {
    await setUpYesNo();
    final s = h.controller.session!;
    endPrompt();
    expect(s.phase, SessionPhase.playing);
    final correct = q0().correctIndex == 0;
    h.controller.debugInject(HandRaised(Hand.left, at: h.lastFrameAt));
    expect(s.round.chosenIndex, 0);
    expect(s.lastResult, correct ? RoundResult.correct : RoundResult.wrong);
  });

  test('a right hand answers Sai (choice 1) while playing', () async {
    await setUpYesNo();
    final s = h.controller.session!;
    endPrompt();
    final correct = q0().correctIndex == 1;
    h.controller.debugInject(HandRaised(Hand.right, at: h.lastFrameAt));
    expect(s.round.chosenIndex, 1);
    expect(s.lastResult, correct ? RoundResult.correct : RoundResult.wrong);
  });

  test('touch fallback answerYesNo answers the tapped choice', () async {
    await setUpYesNo();
    final s = h.controller.session!;
    endPrompt();
    final correct = q0().correctIndex == 1;
    var notified = 0;
    h.controller.addListener(() => notified++);
    h.controller.answerYesNo(1);
    expect(s.round.chosenIndex, 1);
    expect(s.lastResult, correct ? RoundResult.correct : RoundResult.wrong);
    expect(notified, greaterThan(0));
  });

  test(
    'answerYesNo during the prompt or out of range grades nothing',
    () async {
      await setUpYesNo();
      final s = h.controller.session!;
      h.controller.answerYesNo(0); // prompt still being read
      expect(s.phase, SessionPhase.prompting);
      expect(s.round.result, isNull);
      endPrompt();
      h.controller.answerYesNo(2);
      h.controller.answerYesNo(-1);
      expect(s.round.result, isNull);
      expect(s.lastResult, isNull);
    },
  );

  test('a hand raised during the prompt is ignored', () async {
    await setUpYesNo();
    final s = h.controller.session!;
    final r = s.round as YesNoRound;
    expect(s.phase, SessionPhase.prompting);
    h.controller.debugInject(HandRaised(Hand.left, at: h.lastFrameAt));
    h.controller.debugInject(HandRaised(Hand.right, at: h.lastFrameAt));
    expect(r.result, isNull);
    expect(r.chosenIndex, isNull);
    endPrompt();
    expect(s.phase, SessionPhase.playing);
    expect(r.result, isNull);
    expect(s.lastResult, isNull);
  });

  test('child gone while the question is read: the round waits', () async {
    await setUpYesNo();
    final s = h.controller.session!;
    final r = s.round as YesNoRound;
    h.controller.debugInject(PlayerLost(at: h.lastFrameAt));
    endPrompt();
    expect(s.phase, SessionPhase.playing);
    await h.run(r.timeLimit * 2, withFrames: false);
    expect(s.lastResult, isNull);
    expect(s.round, same(r));
    expect(r.result, isNull);
    expect(r.remaining, r.timeLimit);
    // An answer while lost is not graded.
    h.controller.answerYesNo(0);
    expect(r.result, isNull);
    // The child comes back: the clock resumes.
    h.controller.debugInject(PlayerFound(at: h.lastFrameAt));
    await h.run(const Duration(seconds: 2));
    expect(r.remaining, lessThan(r.timeLimit));
    expect(r.result, isNull);
  });

  group('post-answer explanation', () {
    Future<void> answerWrong(GameHarness h) async {
      final s = h.controller.session!;
      h.controller.debugInject(
        HandRaised(
          (s.current.question as ChoiceQuestion).correctIndex == 0
              ? Hand.right
              : Hand.left,
          at: h.lastFrameAt,
        ),
      );
      expect(s.phase, SessionPhase.feedback);
      await pumpEventQueue(times: 20);
    }

    test('a true statement is repeated, not announced as the answer', () async {
      await setUpYesNo(hangTts: false, want: (q) => q.correctIndex == 0);
      final q = q0();
      endPrompt();
      h.ttsLog.clear();
      h.captions.clear();
      await answerWrong(h);
      expect(h.ttsLog, contains('tts:${q.ttsText}'));
      expect(h.captions, isNot(contains(VoiceLine.theAnswerIs.caption)));
    });

    test('a false statement speaks the real word of the picture', () async {
      await setUpYesNo(hangTts: false, want: (q) => q.correctIndex == 1);
      final q = q0();
      final word = harnessWords[int.parse(q.itemId.split('i').last)];
      endPrompt();
      h.ttsLog.clear();
      h.captions.clear();
      await answerWrong(h);
      expect(h.captions, contains(VoiceLine.theAnswerIs.caption));
      expect(h.ttsLog, contains('tts:$word'));
    });
  });

  test(
    'mixed laneJump/catchIt/yesNo: all three play, lanes stay clean',
    () async {
      h = await GameHarness.create(
        level: _level4,
        grade: 1,
        shuffle: true,
        withImages: true,
        modes: const [ModeKind.laneJump, ModeKind.catchIt, ModeKind.yesNo],
      );
      await h.startAndCalibrate();
      final s = h.controller.session!;
      // Lane 2 of 3 lanes (and of 4), but lane 1 if a 2-lane tracker leaked.
      final w = GameHarness.hipXForLane(0, 3) - GameHarness.hipXForLane(1, 3);
      final x = GameHarness.hipXForLane(1, 3) - 0.9 * w;
      final seen = <ModeKind>{};
      final lanes = <int>[];
      Round? last;
      for (var i = 0; i < 800 && s.phase != SessionPhase.finished; i++) {
        await h.run(
          const Duration(milliseconds: 500),
          pose: (_) => makePose(hipX: x),
        );
        final r = s.round;
        if (s.phase != SessionPhase.playing || identical(r, last)) continue;
        last = r;
        if (r is YesNoRound) {
          seen.add(ModeKind.yesNo);
          lanes.add(h.controller.selectedLane);
          expect(r.question.choices.length, 2);
          h.controller.answerYesNo(0);
        } else if (r is LaneJumpRound) {
          seen.add(ModeKind.laneJump);
          expect(r.question.choices.length, 4);
        } else if (r is CatchItRound) {
          seen.add(ModeKind.catchIt);
        }
      }
      expect(seen, {ModeKind.laneJump, ModeKind.catchIt, ModeKind.yesNo});
      expect(s.phase, SessionPhase.finished);
      // Never re-counted to 2 lanes for the two-choice question.
      expect(lanes, isNotEmpty);
      expect(lanes.every((l) => l == 2), isTrue, reason: '$lanes');
    },
  );
}
