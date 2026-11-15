import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/history_store.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/action_detector.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/levels/level_config.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/session/level_session.dart';

import '../helpers/capture_print.dart';

class FakeRound implements Round {
  FakeRound(this.pq, this.review);
  final PlannedQuestion pq;
  final bool review;
  bool started = false;
  int ticks = 0;
  final events = <GameInputEvent>[];
  RoundResult? _result;
  Duration _remaining = const Duration(seconds: 10);

  void setResult(RoundResult r) => _result = r;

  @override
  void start() => started = true;
  @override
  void onEvent(GameInputEvent e) => events.add(e);
  @override
  void tick(Duration dt) {
    ticks++;
    if (started && _result == null) _remaining -= dt;
  }

  @override
  RoundResult? get result => _result;
  @override
  int? get chosenIndex => null;
  @override
  Duration get remaining => _remaining;
  @override
  bool get clockRunning => started && _result == null;
  @override
  Duration get timeLimit => const Duration(seconds: 10);
  @override
  double get elapsedFraction =>
      (1 - _remaining.inMilliseconds / timeLimit.inMilliseconds).clamp(
        0.0,
        1.0,
      );
}

class SlowHistory extends RecordingHistory {
  final log = <String>[];
  Future<void> _op(String name, Future<void> Function() f) async {
    log.add('start $name');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await f();
    log.add('end $name');
  }

  @override
  Future<void> recordAsked(List<String> ids) =>
      _op('asked', () => super.recordAsked(ids));
  @override
  Future<void> markWrong(String id) =>
      _op('wrong:$id', () => super.markWrong(id));
  @override
  Future<void> clearWrong(String id) =>
      _op('clear:$id', () => super.clearWrong(id));
}

class ThrowingHistory extends RecordingHistory {
  @override
  Future<void> recordAsked(List<String> ids) async => throw StateError('x');
  @override
  Future<void> markWrong(String id) async => throw StateError('x');
  @override
  Future<void> clearWrong(String id) async => throw StateError('x');
}

class RecordingHistory extends InMemoryHistoryStore {
  final calls = <String>[];
  @override
  Future<void> recordAsked(List<String> ids) {
    calls.add('asked:${ids.join(",")}');
    return super.recordAsked(ids);
  }

  @override
  Future<void> markWrong(String id) {
    calls.add('wrong:$id');
    return super.markWrong(id);
  }

  @override
  Future<void> clearWrong(String id) {
    calls.add('clear:$id');
    return super.clearWrong(id);
  }
}

PlannedQuestion pqOf(
  String id, [
  QuestionForm form = QuestionForm.listenPickWord,
]) => PlannedQuestion(
  mode: ModeKind.laneJump,
  question: ChoiceQuestion(
    itemId: id,
    form: form,
    ttsText: id,
    choices: const [],
    correctIndex: 0,
  ),
);

const level = LevelConfig(
  level: 1,
  questionCount: 8,
  baseTime: Duration(seconds: 10),
  choiceCount: 3,
  hints: HintMode.full,
  window: UnitWindow.current,
);

const ms = Duration(milliseconds: 16);
const feedback = Duration(milliseconds: 2500);

class Harness {
  Harness(
    int n, {
    Duration? feedbackTime,
    RecordingHistory? h,
    HintMode hints = HintMode.full,
    QuestionForm form = QuestionForm.listenPickWord,
  }) : history = h ?? RecordingHistory(),
       plan = [for (var i = 0; i < n; i++) pqOf('i$i', form)] {
    session = LevelSession(
      level: LevelConfig(
        level: 1,
        questionCount: 8,
        baseTime: const Duration(seconds: 10),
        choiceCount: 3,
        hints: hints,
        window: UnitWindow.current,
      ),
      plan: plan,
      history: history,
      feedbackTime: feedbackTime ?? feedback,
      makeRound: (pq, {required bool review}) {
        final r = FakeRound(pq, review);
        rounds.add(r);
        return r;
      },
    );
  }
  final RecordingHistory history;
  final List<PlannedQuestion> plan;
  final rounds = <FakeRound>[];
  late final LevelSession session;
  FakeRound get cur => rounds.last;

  /// prompt -> result -> feedback elapsed.
  void answer(RoundResult r) {
    session.onPromptFinished();
    cur.setResult(r);
    session.tick(ms);
    expect(session.phase, SessionPhase.feedback);
    session.tick(feedback);
  }
}

void main() {
  test('correctCount counts first-attempt correct answers only', () {
    final h = Harness(3)..session.begin();
    expect(h.session.correctCount, 0);
    h.answer(RoundResult.correct);
    expect(h.session.correctCount, 1);
    h.answer(RoundResult.wrong);
    expect(h.session.correctCount, 1);
    h.answer(RoundResult.correct);
    h.answer(RoundResult.correct); // review of the wrong one
    expect(h.session.correctCount, 2);
    expect(h.session.outcome!.correct, 2);
  });

  test('begin enters prompting with a non-review round', () {
    final h = Harness(3)..session.begin();
    expect(h.session.phase, SessionPhase.prompting);
    expect(h.session.isReview, isFalse);
    expect(h.session.current, same(h.plan[0]));
    expect(h.session.outcome, isNull);
    expect(h.cur.started, isFalse);
    expect(h.session.totalQuestions, 3);
    expect(h.session.index, 0);
  });

  test('onPromptFinished starts the round; ignored outside prompting', () {
    final h = Harness(2)..session.begin();
    h.session.onPromptFinished();
    expect(h.session.phase, SessionPhase.playing);
    expect(h.cur.started, isTrue);
    h.session.onPromptFinished();
    expect(h.session.phase, SessionPhase.playing);
  });

  test('tick in prompting does not reduce remaining', () {
    final h = Harness(2)..session.begin();
    final before = h.session.round.remaining;
    h.session.tick(const Duration(seconds: 5));
    expect(h.session.round.remaining, before);
    expect(h.cur.ticks, 0);
  });

  test('events forwarded only in playing, incl. PlayerLost/Found', () {
    final h = Harness(2)..session.begin();
    const c = Confirmed(0, at: Duration.zero);
    h.session.onEvent(c);
    expect(h.cur.events, isEmpty);
    h.session.onPromptFinished();
    h.session.onEvent(const PlayerLost(at: Duration.zero));
    h.session.onEvent(c);
    h.session.onEvent(const PlayerFound(at: Duration.zero));
    expect(h.cur.events, hasLength(3));
    expect(h.cur.events.first, isA<PlayerLost>());
  });

  test('result after onEvent enters feedback and later input is dropped', () {
    final h = Harness(2)..session.begin();
    h.session.onPromptFinished();
    h.cur.setResult(RoundResult.wrong);
    h.session.onEvent(const Confirmed(1, at: Duration.zero));
    expect(h.session.phase, SessionPhase.feedback);
    expect(h.session.lastResult, RoundResult.wrong);
    h.session.onEvent(const Confirmed(2, at: Duration.zero));
    expect(h.cur.events, hasLength(1));
    h.session.tick(ms);
    expect(h.cur.ticks, 0);
  });

  test('feedback counts down then advances to next prompting', () {
    final h = Harness(2)..session.begin();
    h.session.onPromptFinished();
    h.cur.setResult(RoundResult.correct);
    h.session.tick(ms);
    h.session.tick(const Duration(milliseconds: 2499));
    expect(h.session.phase, SessionPhase.feedback);
    h.session.tick(const Duration(milliseconds: 1));
    expect(h.session.phase, SessionPhase.prompting);
    expect(h.rounds, hasLength(2));
    expect(h.session.current, same(h.plan[1]));
    expect(h.session.index, 1);
    expect(h.session.lastResult, isNull);
  });

  test('8 questions, 6 correct: outcome and review round-trip', () {
    final h = Harness(8)..session.begin();
    const results = [
      RoundResult.correct,
      RoundResult.wrong,
      RoundResult.correct,
      RoundResult.correct,
      RoundResult.timeout,
      RoundResult.correct,
      RoundResult.correct,
      RoundResult.correct,
    ];
    for (final r in results) {
      expect(h.session.isReview, isFalse);
      h.answer(r);
    }
    // The 2 failed questions come back at the end, in order, as reviews.
    expect(h.session.phase, SessionPhase.prompting);
    expect(h.session.isReview, isTrue);
    expect(h.session.current, same(h.plan[1]));
    expect(h.session.totalQuestions, 8);
    h.answer(RoundResult.correct);
    expect(h.session.isReview, isTrue);
    expect(h.session.current, same(h.plan[4]));
    expect(h.session.outcome, isNull);
    h.answer(RoundResult.correct);

    expect(h.session.phase, SessionPhase.finished);
    final o = h.session.outcome!;
    expect(o.correct, 6);
    expect(o.total, 8);
    expect(o.points, 600);
    expect(o.stars, 2);
    expect(o.unlockedNext, isTrue);
    expect(h.rounds.map((r) => r.review), [
      ...List.filled(8, false),
      true,
      true,
    ]);
  });

  test('wrong answers in review do not add reviews or points', () {
    final h = Harness(2)..session.begin();
    h.answer(RoundResult.wrong);
    h.answer(RoundResult.correct);
    h.answer(RoundResult.wrong); // review of i0, wrong again
    expect(h.session.phase, SessionPhase.finished);
    expect(h.rounds, hasLength(3));
    final o = h.session.outcome!;
    expect((o.correct, o.total, o.points, o.stars), (1, 2, 100, 1));
    expect(o.unlockedNext, isTrue);
  });

  test('timeout in review ends the level too (no re-review)', () {
    final h = Harness(1)..session.begin();
    h.answer(RoundResult.timeout);
    h.answer(RoundResult.timeout);
    expect(h.session.phase, SessionPhase.finished);
    expect(h.rounds, hasLength(2));
  });

  test('all wrong: stars 0, unlockedNext false', () {
    final h = Harness(2)..session.begin();
    for (var i = 0; i < 4; i++) {
      h.answer(RoundResult.wrong);
    }
    final o = h.session.outcome!;
    expect((o.correct, o.stars, o.points), (0, 0, 0));
    expect(o.unlockedNext, isFalse);
  });

  test(
    'history: asked 8 ids, markWrong 2, clearWrong 6 (+fixed in review)',
    () async {
      final store = RecordingHistory();
      final h = Harness(8, h: store)..session.begin();
      const results = [
        RoundResult.correct,
        RoundResult.wrong, // i1: fixed in review
        RoundResult.correct,
        RoundResult.correct,
        RoundResult.timeout, // i4: wrong again in review
        RoundResult.correct,
        RoundResult.correct,
        RoundResult.correct,
      ];
      for (final r in results) {
        h.answer(r);
      }
      expect(store.calls, isEmpty, reason: 'history is written only at finish');
      h.answer(RoundResult.correct); // review i1
      h.answer(RoundResult.wrong); // review i4
      await h.session.historyWritten;
      expect(store.calls.where((c) => c.startsWith('asked:')), [
        'asked:i0,i1,i2,i3,i4,i5,i6,i7',
      ]);
      expect(store.calls.where((c) => c.startsWith('wrong:')), ['wrong:i4']);
      expect(
        store.calls.where((c) => c.startsWith('clear:')).toSet(),
        {
          'i0',
          'i1',
          'i2',
          'i3',
          'i5',
          'i6',
          'i7',
        }.map((i) => 'clear:$i').toSet(),
      );
      // Never both mark and clear for one item.
      expect(store.calls.contains('clear:i4'), isFalse);
      expect(store.calls.contains('wrong:i1'), isFalse);
      expect(store.wrongIds(), {'i4'});
      expect(store.recentIds(), hasLength(8));
    },
  );

  test('action questions are not recorded in history, mixed plan', () async {
    final store = RecordingHistory();
    final plan = [
      pqOf('i0'),
      const PlannedQuestion(
        mode: ModeKind.puppySays,
        question: ActionQuestion(
          itemId: 'act-jump',
          ttsText: 'Jump!',
          command: 'jump',
          hintVi: 'Nhảy lên',
          action: PuppyAction.jump,
        ),
      ),
    ];
    final session = LevelSession(
      level: level,
      plan: plan,
      history: store,
      feedbackTime: feedback,
      makeRound: (pq, {required bool review}) => FakeRound(pq, review),
    )..begin();
    for (final r in [RoundResult.correct, RoundResult.timeout]) {
      session.onPromptFinished();
      (session.round as FakeRound).setResult(r);
      session.tick(ms);
      session.tick(feedback);
    }
    // The timed-out action gets a review round (stars/unlock unchanged).
    session.onPromptFinished();
    (session.round as FakeRound).setResult(RoundResult.correct);
    session.tick(ms);
    session.tick(feedback);
    expect(session.phase, SessionPhase.finished);
    await session.historyWritten;
    expect(store.calls.where((c) => c.startsWith('asked:')), ['asked:i0']);
    expect(store.calls.any((c) => c.contains('act-jump')), isFalse);
    expect(store.recentIds(), ['i0']);
    expect(store.wrongIds(), isEmpty);
    expect(session.outcome!.correct, 1);
    expect(session.outcome!.total, 2);
  });

  test(
    'history seeded with a wrong id is cleared when answered correctly',
    () async {
      final store = RecordingHistory();
      await store.markWrong('i0');
      final h = Harness(1, h: store)..session.begin();
      h.answer(RoundResult.correct);
      await h.session.historyWritten;
      expect(store.wrongIds(), isEmpty);
    },
  );

  test('pause in playing: tick does nothing, resume restores playing', () {
    final h = Harness(2)..session.begin();
    h.session.onPromptFinished();
    final before = h.session.round.remaining;
    h.session.pause();
    expect(h.session.phase, SessionPhase.paused);
    h.session.tick(const Duration(seconds: 10));
    h.session.onEvent(const Confirmed(0, at: Duration.zero));
    expect(h.session.round.remaining, before);
    expect(h.cur.ticks, 0);
    expect(h.cur.events, isEmpty);
    h.session.resume();
    expect(h.session.phase, SessionPhase.playing);
    expect(h.session.round.remaining, before);
    h.session.tick(ms);
    expect(h.cur.ticks, 1);
  });

  test('pause in prompting without prompt end resumes to prompting', () {
    final h = Harness(2)..session.begin();
    h.session.pause();
    h.session.tick(const Duration(seconds: 10));
    expect(h.session.phase, SessionPhase.paused);
    h.session.resume();
    expect(h.session.phase, SessionPhase.prompting);
    expect(h.cur.started, isFalse);
  });

  test('onPromptFinished while paused from prompting is latched to resume', () {
    final h = Harness(2)..session.begin();
    h.session.pause();
    h.session.onPromptFinished();
    expect(h.session.phase, SessionPhase.paused);
    expect(h.cur.started, isFalse);
    h.session.resume();
    expect(h.session.phase, SessionPhase.playing);
    expect(h.cur.started, isTrue);
  });

  test('onPromptFinished while paused from another phase is ignored', () {
    final h = Harness(2)..session.begin();
    h.session.onPromptFinished();
    h.session.pause();
    h.session.onPromptFinished();
    h.session.resume();
    expect(h.session.phase, SessionPhase.playing);
    // Latch must not leak into the next question.
    h.cur.setResult(RoundResult.correct);
    h.session.tick(ms);
    h.session.pause();
    h.session.onPromptFinished();
    h.session.resume();
    h.session.tick(feedback);
    expect(h.session.phase, SessionPhase.prompting);
    expect(h.cur.started, isFalse);
  });

  test('input before begin is ignored', () {
    final h = Harness(2);
    h.session.onPromptFinished();
    h.session.tick(ms);
    h.session.onEvent(const Confirmed(0, at: Duration.zero));
    h.session.pause();
    expect(h.rounds, isEmpty);
    h.session.begin();
    expect(h.session.phase, SessionPhase.prompting);
  });

  test('makeRound throwing once does not skip a question', () {
    var fail = false;
    final rounds = <FakeRound>[];
    final s = LevelSession(
      level: level,
      plan: [pqOf('a'), pqOf('b')],
      history: InMemoryHistoryStore(),
      makeRound: (pq, {required bool review}) {
        if (fail) {
          fail = false;
          throw StateError('boom');
        }
        final r = FakeRound(pq, review);
        rounds.add(r);
        return r;
      },
    )..begin();
    s.onPromptFinished();
    rounds.last.setResult(RoundResult.correct);
    s.tick(ms);
    fail = true;
    expect(() => s.tick(feedback), throwsStateError);
    expect(s.phase, SessionPhase.feedback);
    expect(s.current.question.itemId, 'a');
    s.tick(ms);
    expect(s.phase, SessionPhase.prompting);
    expect(s.current.question.itemId, 'b');
  });

  test(
    'history writes are sequential and complete after historyWritten',
    () async {
      final store = SlowHistory();
      final h = Harness(3, h: store)..session.begin();
      h.answer(RoundResult.wrong);
      h.answer(RoundResult.correct);
      h.answer(RoundResult.correct);
      h.answer(RoundResult.correct); // review of i0
      expect(h.session.phase, SessionPhase.finished);
      await h.session.historyWritten;
      expect(store.log, [
        'start asked',
        'end asked',
        'start clear:i0',
        'end clear:i0',
        'start clear:i1',
        'end clear:i1',
        'start clear:i2',
        'end clear:i2',
      ]);
    },
  );

  test('failing history store does not break the session', () async {
    final printed = <String>[];
    await captureDebugPrint(printed, () async {
      final h = Harness(2, h: ThrowingHistory())..session.begin();
      h.answer(RoundResult.correct);
      h.answer(RoundResult.wrong);
      h.answer(RoundResult.wrong);
      expect(h.session.phase, SessionPhase.finished);
      final o = h.session.outcome!;
      expect((o.correct, o.total, o.stars), (1, 2, 1));
      await h.session.historyWritten; // completes normally
    });
    expect(printed, ['LevelSession: history write failed: Bad state: x']);
  });

  test('pause in feedback does not burn feedback time', () {
    final h = Harness(2)..session.begin();
    h.session.onPromptFinished();
    h.cur.setResult(RoundResult.correct);
    h.session.tick(ms);
    h.session.pause();
    h.session.tick(const Duration(seconds: 10));
    expect(h.session.phase, SessionPhase.paused);
    expect(h.rounds, hasLength(1));
    h.session.resume();
    expect(h.session.phase, SessionPhase.feedback);
    h.session.tick(const Duration(milliseconds: 2499));
    expect(h.session.phase, SessionPhase.feedback);
    h.session.tick(const Duration(milliseconds: 1));
    expect(h.session.phase, SessionPhase.prompting);
  });

  test(
    'pause when finished or already paused is a no-op; resume w/o pause too',
    () {
      final h = Harness(1)..session.begin();
      h.session.resume();
      expect(h.session.phase, SessionPhase.prompting);
      h.answer(RoundResult.correct);
      expect(h.session.phase, SessionPhase.finished);
      h.session.pause();
      expect(h.session.phase, SessionPhase.finished);

      final g = Harness(1)..session.begin();
      g.session.pause();
      g.session.pause();
      g.session.resume();
      expect(g.session.phase, SessionPhase.prompting);
    },
  );

  test(
    'history is written exactly once even when ticked after finish',
    () async {
      final h = Harness(1)..session.begin();
      h.answer(RoundResult.correct);
      await h.session.historyWritten;
      final n = h.history.calls.length;
      h.session.tick(const Duration(seconds: 10));
      h.session.onEvent(const Confirmed(0, at: Duration.zero));
      h.session.onPromptFinished();
      expect(h.history.calls, hasLength(n));
      expect(h.session.phase, SessionPhase.finished);
    },
  );

  test('empty plan finishes immediately with zero stars', () {
    final h = Harness(0)..session.begin();
    expect(h.session.phase, SessionPhase.finished);
    final o = h.session.outcome!;
    expect((o.correct, o.total, o.points, o.stars), (0, 0, 0, 0));
    expect(o.unlockedNext, isFalse);
    expect(h.rounds, isEmpty);
  });

  group('tile hints (LevelConfig.hints for LaneJump word tiles)', () {
    test('exposes the hint mode and the round elapsed fraction', () {
      final h = Harness(2, hints: HintMode.partial)..session.begin();
      expect(h.session.hintMode, HintMode.partial);
      expect(h.session.roundElapsedFraction, 0);
      h.session.onPromptFinished();
      h.session.tick(const Duration(seconds: 4));
      expect(h.session.roundElapsedFraction, closeTo(0.4, 1e-9));
    });

    test('full: pictures from the very start, even while the prompt plays', () {
      final h = Harness(2, hints: HintMode.full)..session.begin();
      expect(h.session.showTileHints, isTrue);
      h.session.onPromptFinished();
      expect(h.session.showTileHints, isTrue);
      h.session.tick(const Duration(seconds: 9));
      expect(h.session.showTileHints, isTrue);
    });

    test('partial: pictures appear once 50% of the time limit has elapsed', () {
      final h = Harness(2, hints: HintMode.partial)..session.begin();
      expect(h.session.showTileHints, isFalse);
      h.session.onPromptFinished();
      expect(h.session.showTileHints, isFalse);
      h.session.tick(const Duration(milliseconds: 4900));
      expect(h.session.showTileHints, isFalse);
      h.session.tick(const Duration(milliseconds: 100)); // exactly 50%
      expect(h.session.showTileHints, isTrue);
    });

    test('partial: the next question starts hidden again', () {
      final h = Harness(3, hints: HintMode.partial)..session.begin();
      h.session.onPromptFinished();
      h.session.tick(const Duration(seconds: 6));
      expect(h.session.showTileHints, isTrue);
      h.cur.setResult(RoundResult.wrong);
      h.session.tick(ms);
      h.session.tick(feedback);
      expect(h.session.phase, SessionPhase.prompting);
      expect(h.session.showTileHints, isFalse);
    });

    test('none: never', () {
      final h = Harness(2, hints: HintMode.none)..session.begin();
      h.session.onPromptFinished();
      h.session.tick(const Duration(seconds: 9));
      expect(h.session.showTileHints, isFalse);
    });

    test('showPromptHint: the prompt picture of DragSpell / SkyShoot follows '
        'the same rule, whatever the question form', () {
      final full = Harness(2, hints: HintMode.full)..session.begin();
      expect(full.session.showPromptHint, isTrue);

      final none = Harness(2, hints: HintMode.none)..session.begin();
      none.session.onPromptFinished();
      none.session.tick(const Duration(seconds: 9));
      expect(none.session.showPromptHint, isFalse);

      final partial = Harness(2, hints: HintMode.partial)..session.begin();
      expect(partial.session.showPromptHint, isFalse);
      partial.session.onPromptFinished();
      partial.session.tick(const Duration(milliseconds: 4900));
      expect(partial.session.showPromptHint, isFalse);
      partial.session.tick(const Duration(milliseconds: 100));
      expect(partial.session.showPromptHint, isTrue);
    });

    test('picture-based forms are unaffected in every mode', () {
      for (final form in [
        QuestionForm.seePicturePickWord,
        QuestionForm.listenPickPicture,
        QuestionForm.fillBlank,
      ]) {
        for (final mode in HintMode.values) {
          final h = Harness(2, hints: mode, form: form)..session.begin();
          h.session.onPromptFinished();
          h.session.tick(const Duration(seconds: 9));
          expect(h.session.showTileHints, isFalse, reason: '$form $mode');
        }
      }
    });

    test('not shown once the level is finished', () {
      final h = Harness(1, hints: HintMode.full)..session.begin();
      h.answer(RoundResult.correct);
      expect(h.session.phase, SessionPhase.finished);
      expect(h.session.showTileHints, isFalse);
    });
  });
}
