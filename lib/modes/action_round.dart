import '../content/question_models.dart';
import '../input/game_input_event.dart';
import 'round.dart';

/// puppySays: the puppy names an action; performing exactly that action while
/// the clock runs is [RoundResult.correct]. Other actions are ignored (the
/// round is never graded wrong, only [RoundResult.timeout] when [timeLimit]
/// runs out). Ignored before [start] and while the player is lost; later
/// events after the result change nothing.
class ActionRound implements Round {
  ActionRound(this.question, {required this.timeLimit})
    : _remaining = timeLimit;

  final ActionQuestion question;
  Duration _remaining;
  bool _started = false;
  bool _playerPresent = true;
  RoundResult? _result;

  @override
  RoundResult? get result => _result;

  @override
  int? get chosenIndex => null;

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
  bool get clockRunning => _started && _playerPresent && _result == null;

  @override
  void start() => _started = true;

  @override
  void onEvent(GameInputEvent e) {
    if (_result != null) return;
    switch (e) {
      case ActionPerformed(:final action):
        if (clockRunning && action == question.action) {
          _result = RoundResult.correct;
        }
      case PlayerLost():
        _playerPresent = false;
      case PlayerFound():
        _playerPresent = true;
      case LaneChanged() ||
          HandRaised() ||
          Confirmed() ||
          CursorMoved() ||
          Pulled():
        break;
    }
  }

  @override
  void tick(Duration dt) {
    if (dt <= Duration.zero || !clockRunning) return;
    _remaining -= dt;
    if (_remaining <= Duration.zero) {
      _remaining = Duration.zero;
      _result = RoundResult.timeout;
    }
  }
}
