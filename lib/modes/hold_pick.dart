import 'dart:ui' show Rect, Offset;

import '../content/question_models.dart';
import '../input/game_input_event.dart';
import '../input/hold_tracker.dart';
import 'round.dart';

/// memoryFlip / balloonPop: pick one of the question's choices by holding the
/// hand cursor over it for [holdTime] (or by a tap, see [onTargetHeld]).
///
/// The cursor (normalised 0..1) is mapped to `choice:<i>` with [targetRect]
/// (nearest centre when rects overlap, null outside every rect) and fed to a
/// [HoldTracker] with the events' frame timestamps, never the wall clock.
/// Sweeping across targets restarts the hold at each one.
///
/// With a [peek] the choices are shown face-up for that long once the round
/// has started: the clock and the cursor are inert meanwhile ([peeking]).
/// Cursor state is reset by [start] and by [PlayerLost] / [PlayerFound], so a
/// stale hold can never complete from before play began or while absent.
class HoldPickRound implements Round {
  HoldPickRound(
    this.question, {
    required this.timeLimit,
    required Duration holdTime,
    this.peek = Duration.zero,
    required this.targetRect,
  }) : assert(question.choices.isNotEmpty, 'a question needs choices'),
       _tracker = HoldTracker(holdTime: holdTime),
       _remaining = timeLimit,
       _peekLeft = peek;

  final ChoiceQuestion question;
  final Duration peek;

  /// Normalised (0..1) rect of choice `i`.
  final Rect Function(int choice) targetRect;

  final HoldTracker _tracker;
  Duration _remaining;
  Duration _peekLeft;
  bool _started = false;
  bool _playerPresent = true;
  RoundResult? _result;
  int? _chosenIndex;
  int? _hover;
  double _progress = 0;

  static final RegExp _target = RegExp(r'^choice:(\d+)$');

  /// Choice the cursor is on (null: none).
  int? get hoverIndex => _hover;

  /// Target id of the hovered choice (`choice:<i>`), null when none.
  String? get hoverTarget => _hover == null ? null : 'choice:$_hover';

  /// 0..1 progress of the current hold.
  double get holdProgress => _progress;

  /// Choices are face-up (memoryFlip) and nothing can be picked yet.
  bool get peeking => _started && _result == null && _peekLeft > Duration.zero;

  @override
  RoundResult? get result => _result;

  @override
  int? get chosenIndex => _chosenIndex;

  @override
  Duration get remaining => _remaining;

  @override
  final Duration timeLimit;

  @override
  double get elapsedFraction {
    final limit = timeLimit.inMicroseconds;
    if (limit <= 0) return 1.0;
    return (1 - _remaining.inMicroseconds / limit).clamp(0.0, 1.0);
  }

  @override
  bool get clockRunning =>
      _started && _playerPresent && _result == null && !peeking;

  @override
  void start() {
    _started = true;
    _resetHold();
  }

  void _resetHold() {
    _tracker.reset();
    _hover = null;
    _progress = 0;
  }

  /// Choice under the normalised point, nearest centre when rects overlap.
  int? _hit(double x, double y) {
    final p = Offset(x, y);
    int? best;
    var bestD = double.infinity;
    for (var i = 0; i < question.choices.length; i++) {
      final r = targetRect(i);
      if (!r.contains(p)) continue;
      final d = (r.center - p).distanceSquared;
      if (d < bestD) {
        bestD = d;
        best = i;
      }
    }
    return best;
  }

  @override
  void onEvent(GameInputEvent e) {
    if (_result != null) return;
    switch (e) {
      case PlayerLost():
        _playerPresent = false;
        _resetHold();
      case PlayerFound():
        _playerPresent = true;
        _resetHold();
      case CursorMoved(:final x, :final y, :final at):
        if (!_started || !_playerPresent || peeking) return;
        final hit = _hit(x, y);
        final p = _tracker.update(hit == null ? null : 'choice:$hit', at);
        _hover = hit;
        _progress = p.progress;
        if (p.completed && hit != null) _pick(hit);
      case LaneChanged() || Confirmed() || Pulled():
        break;
    }
  }

  void _pick(int i) {
    _chosenIndex = i;
    _result = i == question.correctIndex
        ? RoundResult.correct
        : RoundResult.wrong;
  }

  /// A tap (or any external completed hold) on `choice:<i>`. Ignored before
  /// the round started, during the peek, while the player is lost, for
  /// unknown ids and once the round has a result.
  void onTargetHeld(String targetId) {
    if (!_started || !_playerPresent || _result != null || peeking) return;
    final m = _target.firstMatch(targetId);
    if (m == null) return;
    final i = int.parse(m.group(1)!);
    if (i >= question.choices.length) return;
    _pick(i);
  }

  @override
  void tick(Duration dt) {
    if (dt <= Duration.zero ||
        !_started ||
        !_playerPresent ||
        _result != null) {
      return;
    }
    if (_peekLeft > Duration.zero) {
      _peekLeft -= dt;
      if (_peekLeft < Duration.zero) _peekLeft = Duration.zero;
      // The peek ends: the cursor starts from scratch.
      if (_peekLeft == Duration.zero) _resetHold();
      return;
    }
    _remaining -= dt;
    if (_remaining <= Duration.zero) {
      _remaining = Duration.zero;
      _result = RoundResult.timeout;
    }
  }
}
