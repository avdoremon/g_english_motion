import '../content/question_models.dart';
import '../input/game_input_event.dart';
import 'round.dart';

/// "Hứng hình": pictures fall in lanes for [timeLimit]; the lane the child is
/// in when they reach the catch line is the answer. [Confirmed] is ignored and
/// the round never times out: the catch line itself grades it.
class CatchItRound implements Round {
  CatchItRound(
    this.question, {
    required this.timeLimit,
    required int initialLane,
  }) : assert(question.choices.isNotEmpty, 'a question needs choices'),
       _remaining = timeLimit,
       _lane = initialLane.clamp(0, question.choices.length - 1);

  final ChoiceQuestion question;
  Duration _remaining;
  int _lane;
  bool _started = false;
  bool _playerPresent = true;
  RoundResult? _result;
  int? _chosenIndex;

  int get lane => _lane;

  /// Sets the lane from the controller's tracked lane. The session only
  /// forwards [LaneChanged] while playing, so changes made while the question
  /// is being read (or the game is paused) would otherwise be lost.
  void syncLane(int lane) {
    if (_result != null) return;
    _lane = lane.clamp(0, question.choices.length - 1);
  }

  /// How far the pictures have fallen (0 at the top, 1 at the catch line).
  double get fallFraction => elapsedFraction;

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
  bool get clockRunning => _started && _playerPresent && _result == null;

  @override
  void start() => _started = true;

  @override
  void onEvent(GameInputEvent e) {
    if (_result != null) return;
    switch (e) {
      case LaneChanged(:final lane):
        syncLane(lane);
      case PlayerLost():
        _playerPresent = false;
      case PlayerFound():
        _playerPresent = true;
      case Confirmed() || CursorMoved() || Pulled():
        break;
    }
  }

  @override
  void tick(Duration dt) {
    if (dt <= Duration.zero || !clockRunning) return;
    _remaining -= dt;
    if (_remaining <= Duration.zero) {
      _remaining = Duration.zero;
      _chosenIndex = _lane;
      _result = _lane == question.correctIndex
          ? RoundResult.correct
          : RoundResult.wrong;
    }
  }
}
