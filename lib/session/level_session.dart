import 'package:flutter/foundation.dart';

import '../content/history_store.dart';
import '../content/question_models.dart';
import '../input/game_input_event.dart';
import '../levels/level_config.dart';
import '../levels/scoring.dart';
import '../modes/round.dart';
import 'pausable_session.dart';

enum SessionPhase { prompting, playing, feedback, paused, finished }

class LevelOutcome {
  const LevelOutcome({
    required this.correct,
    required this.total,
    required this.points,
    required this.stars,
    required this.unlockedNext,
  });

  final int correct, total, points, stars;
  final bool unlockedNext;
}

class _Entry {
  const _Entry(this.pq, {required this.review});
  final PlannedQuestion pq;
  final bool review;
}

/// Orchestrates one level play-through (pure Dart, no Flutter/clock).
///
/// Flow: [begin] -> prompting (UI reads the question aloud) ->
/// [onPromptFinished] starts the round -> playing -> result -> feedback
/// ([feedbackTime]) -> next question or finished.
///
/// Ordering rule: within one frame the caller applies input events before
/// [tick]. As soon as the round reports a result (after either an event or a
/// tick) the session enters feedback; any later input for that round is
/// ignored, and the round itself ignores input once its result is set.
///
/// A question answered wrong / timed out on its first attempt is appended
/// once to the end of the queue as a review question. Reviews never affect
/// points, correct or total, and never spawn further reviews.
class LevelSession implements PausableSession {
  LevelSession({
    required this.level,
    required List<PlannedQuestion> plan,
    required this.makeRound,
    required this.history,
    this.feedbackTime = const Duration(milliseconds: 2500),
  }) : plan = List.unmodifiable(plan),
       _queue = [for (final p in plan) _Entry(p, review: false)];

  final LevelConfig level;
  final List<PlannedQuestion> plan;
  final Round Function(PlannedQuestion pq, {required bool review}) makeRound;
  final HistoryStore history;
  final Duration feedbackTime;

  final List<_Entry> _queue;
  int _pos = 0;
  Round? _round;
  SessionPhase _phase = SessionPhase.prompting;
  SessionPhase? _phaseBeforePause;
  RoundResult? _lastResult;
  Duration _feedbackElapsed = Duration.zero;
  LevelOutcome? _outcome;
  bool _begun = false;
  bool _promptLatched = false;
  Future<void> _historyWritten = Future<void>.value();

  int _correct = 0;
  final Set<String> _failedFirst = {};
  final Set<String> _fixedInReview = {};

  SessionPhase get phase => _phase;

  /// Throws on an empty plan: the UI must branch on `phase == finished`.
  PlannedQuestion get current => _queue[_pos].pq;
  bool get isReview => _queue[_pos].review;
  RoundResult? get lastResult => _lastResult;
  LevelOutcome? get outcome => _outcome;

  /// First-attempt correct answers so far (reviews never count); the live
  /// basis for the score shown during play. [outcome] stays the source of
  /// truth for stars.
  int get correctCount => _correct;

  /// The active round. Throws before [begin] and on an empty plan: the UI
  /// must branch on `phase == finished`.
  Round get round => _round!;

  /// How the level hints at the answer (from [LevelConfig.hints]).
  HintMode get hintMode => level.hints;

  /// Fraction (0..1) of the current question's time limit that has elapsed;
  /// 0 before the first round and while the question is still being read.
  double get roundElapsedFraction =>
      (_begun && _queue.isNotEmpty) ? _round!.elapsedFraction : 0.0;

  /// Share of the time limit after which [HintMode.partial] reveals the
  /// pictures.
  static const double partialHintAt = 0.5;

  /// Whether the word lanes of the current question show their pictures as a
  /// hint ("Gợi ý hình"). Only the listen-and-pick-word form has word-only
  /// lanes; the picture-based forms are unaffected. The hint is a property of
  /// ALL options (never of the right one), so it cannot give the answer away.
  bool get showTileHints {
    if (!_begun || _queue.isEmpty || _phase == SessionPhase.finished) {
      return false;
    }
    final q = current.question;
    if (q is! ChoiceQuestion || q.form != QuestionForm.listenPickWord) {
      return false;
    }
    return switch (level.hints) {
      HintMode.full => true,
      HintMode.partial => roundElapsedFraction >= partialHintAt,
      HintMode.none => false,
    };
  }

  /// Position among the non-review questions (0-based, capped at the count).
  int get index => _pos < plan.length ? _pos : plan.length;

  /// Number of non-review questions.
  int get totalQuestions => plan.length;

  /// Completes when the end-of-level history writes are done (never throws;
  /// store failures are logged and swallowed). The writes start when the
  /// session finishes; before that this future is already complete (it
  /// completes immediately, there is nothing pending), so await it only after
  /// [phase] is [SessionPhase.finished].
  Future<void> get historyWritten => _historyWritten;

  void begin() {
    if (_begun) return;
    if (_queue.isEmpty) {
      _begun = true;
      _finish();
    } else {
      _enter(0);
      _begun = true;
    }
  }

  void onPromptFinished() {
    if (!_begun) return;
    if (_phase == SessionPhase.paused &&
        _phaseBeforePause == SessionPhase.prompting) {
      // The prompt ended while backgrounded: apply it on resume().
      _promptLatched = true;
      return;
    }
    if (_phase != SessionPhase.prompting) return;
    _round!.start();
    _phase = SessionPhase.playing;
  }

  void onEvent(GameInputEvent e) {
    if (!_begun || _phase != SessionPhase.playing) return;
    _round!.onEvent(e);
    _checkResult();
  }

  void tick(Duration dt) {
    if (!_begun) return;
    switch (_phase) {
      case SessionPhase.playing:
        _round!.tick(dt);
        _checkResult();
      case SessionPhase.feedback:
        _feedbackElapsed += dt;
        if (_feedbackElapsed >= feedbackTime) _advance();
      case SessionPhase.prompting:
      case SessionPhase.paused:
      case SessionPhase.finished:
        break;
    }
  }

  @override
  void pause() {
    if (!_begun ||
        _phase == SessionPhase.paused ||
        _phase == SessionPhase.finished) {
      return;
    }
    _phaseBeforePause = _phase;
    _phase = SessionPhase.paused;
  }

  @override
  void resume() {
    if (_phase != SessionPhase.paused) return;
    _phase = _phaseBeforePause!;
    _phaseBeforePause = null;
    if (_promptLatched) {
      _promptLatched = false;
      onPromptFinished();
    }
  }

  void _enter(int pos) {
    final entry = _queue[pos];
    // Build first: if makeRound throws, state is untouched and the call can
    // be retried (no question is skipped).
    final round = makeRound(entry.pq, review: entry.review);
    _pos = pos;
    _round = round;
    _lastResult = null;
    _feedbackElapsed = Duration.zero;
    _phase = SessionPhase.prompting;
  }

  void _checkResult() {
    final r = _round!.result;
    if (r == null) return;
    _lastResult = r;
    _feedbackElapsed = Duration.zero;
    _phase = SessionPhase.feedback;
    _record(r);
  }

  void _record(RoundResult r) {
    final entry = _queue[_pos];
    final id = entry.pq.question.itemId;
    final ok = r == RoundResult.correct;
    if (entry.review) {
      if (ok) _fixedInReview.add(id);
      return;
    }
    if (ok) {
      _correct++;
    } else {
      _failedFirst.add(id);
      _queue.add(_Entry(entry.pq, review: true));
    }
  }

  void _advance() {
    if (_pos + 1 < _queue.length) {
      _enter(_pos + 1);
    } else {
      _finish();
    }
  }

  void _finish() {
    _phase = SessionPhase.finished;
    final total = plan.length;
    final stars = Scoring.stars(_correct, total);
    _outcome = LevelOutcome(
      correct: _correct,
      total: total,
      points: Scoring.points(_correct),
      stars: stars,
      unlockedNext: Scoring.unlocksNext(stars),
    );
    _historyWritten = _writeHistory();
  }

  // Sequential and failure-proof: a broken store must not break the
  // end-of-level screen.
  Future<void> _writeHistory() async {
    try {
      final asked = <String>{for (final p in plan) p.question.itemId};
      await history.recordAsked(asked.toList());
      final wrong = <String>[];
      final clear = <String>[];
      for (final id in asked) {
        final stillWrong =
            _failedFirst.contains(id) && !_fixedInReview.contains(id);
        (stillWrong ? wrong : clear).add(id);
      }
      for (final id in wrong) {
        await history.markWrong(id);
      }
      for (final id in clear) {
        await history.clearWrong(id);
      }
    } catch (e) {
      debugPrint('LevelSession: history write failed: $e');
    }
  }
}
