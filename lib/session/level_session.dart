import '../content/history_store.dart';
import '../content/question_models.dart';
import '../input/game_input_event.dart';
import '../levels/level_config.dart';
import '../levels/scoring.dart';
import '../modes/round.dart';

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
class LevelSession {
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

  int _correct = 0;
  final Set<String> _failedFirst = {};
  final Set<String> _passedFirst = {};
  final Set<String> _fixedInReview = {};

  SessionPhase get phase => _phase;
  PlannedQuestion get current => _queue[_pos].pq;
  bool get isReview => _queue[_pos].review;
  RoundResult? get lastResult => _lastResult;
  LevelOutcome? get outcome => _outcome;

  /// The active round (valid after [begin] unless the plan is empty).
  Round get round => _round!;

  /// Position among the non-review questions (0-based, capped at the count).
  int get index => _pos < plan.length ? _pos : plan.length;

  /// Number of non-review questions.
  int get totalQuestions => plan.length;

  void begin() {
    if (_begun) return;
    _begun = true;
    if (_queue.isEmpty) {
      _finish();
    } else {
      _enter(0);
    }
  }

  void onPromptFinished() {
    if (_phase != SessionPhase.prompting) return;
    _round!.start();
    _phase = SessionPhase.playing;
  }

  void onEvent(GameInputEvent e) {
    if (_phase != SessionPhase.playing) return;
    _round!.onEvent(e);
    _checkResult();
  }

  void tick(Duration dt) {
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

  void pause() {
    if (_phase == SessionPhase.paused || _phase == SessionPhase.finished) {
      return;
    }
    _phaseBeforePause = _phase;
    _phase = SessionPhase.paused;
  }

  void resume() {
    if (_phase != SessionPhase.paused) return;
    _phase = _phaseBeforePause!;
    _phaseBeforePause = null;
  }

  void _enter(int pos) {
    _pos = pos;
    final entry = _queue[pos];
    _round = makeRound(entry.pq, review: entry.review);
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
      _passedFirst.add(id);
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
    _writeHistory();
  }

  // Fire-and-forget: the store is the source of truth for later reads, and a
  // failed write must not break the end-of-level screen.
  void _writeHistory() {
    final asked = <String>{for (final p in plan) p.question.itemId};
    history.recordAsked(asked.toList());
    for (final id in asked) {
      final stillWrong =
          _failedFirst.contains(id) && !_fixedInReview.contains(id);
      if (stillWrong) {
        history.markWrong(id);
      } else {
        history.clearWrong(id);
      }
    }
  }
}
