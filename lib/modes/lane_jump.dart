import '../content/question_models.dart';
import '../input/game_input_event.dart';
import 'round.dart';

class LaneJumpRound implements Round {
  LaneJumpRound(
    this.question, {
    required this.timeLimit,
    required int initialLane,
  }) : assert(question.choices.isNotEmpty, 'a question needs choices'),
       _remaining = timeLimit,
       _selectedLane = initialLane.clamp(0, question.choices.length - 1);

  final ChoiceQuestion question;
  Duration _remaining;
  int _selectedLane;
  bool _started = false;
  bool _playerPresent = true;
  RoundResult? _result;
  int? _chosenIndex;

  int get selectedLane => _selectedLane;

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
        _selectedLane = lane.clamp(0, question.choices.length - 1);
      case PlayerLost():
        _playerPresent = false;
      case PlayerFound():
        _playerPresent = true;
      case Confirmed(:final lane):
        if (!_started || !_playerPresent) return;
        // Unsure -> do not grade: an out-of-range lane is not a wrong answer.
        if (lane < 0 || lane >= question.choices.length) return;
        _chosenIndex = lane;
        _result = lane == question.correctIndex
            ? RoundResult.correct
            : RoundResult.wrong;
      case CursorMoved() || Pulled():
        break;
    }
  }

  @override
  void tick(Duration dt) {
    // Time never runs backwards (a negative dt would add time back).
    if (dt <= Duration.zero || !clockRunning) return;
    _remaining -= dt;
    if (_remaining <= Duration.zero) {
      _remaining = Duration.zero;
      _result = RoundResult.timeout;
    }
  }
}
