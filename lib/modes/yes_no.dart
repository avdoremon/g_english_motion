import '../content/question_models.dart';
import '../input/game_input_event.dart';
import '../input/pose_types.dart';
import 'round.dart';

/// "Đúng/Sai": a picture and a statement; the left hand is Đúng (choice 0),
/// the right hand Sai (choice 1). A [HandRaised] (or the touch fallback
/// [answer]) grades the round once; later hands change nothing. No answer by
/// [timeLimit] ends as [RoundResult.timeout]. Ignored before [start] and
/// while the player is lost.
class YesNoRound implements Round {
  YesNoRound(this.question, {required this.timeLimit})
    : assert(question.choices.length == 2, 'a yes/no question has 2 choices'),
      _remaining = timeLimit;

  final ChoiceQuestion question;
  Duration _remaining;
  bool _started = false;
  bool _playerPresent = true;
  RoundResult? _result;
  int? _chosenIndex;

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

  /// Answers [index] (0 = Đúng, 1 = Sai). Ignored before [start], while the
  /// player is lost, after a result, and for an out-of-range index (unsure is
  /// never graded wrong).
  void answer(int index) {
    if (!clockRunning) return;
    if (index < 0 || index >= question.choices.length) return;
    _chosenIndex = index;
    _result = index == question.correctIndex
        ? RoundResult.correct
        : RoundResult.wrong;
  }

  @override
  void onEvent(GameInputEvent e) {
    if (_result != null) return;
    switch (e) {
      case HandRaised(:final hand):
        answer(hand == Hand.left ? 0 : 1);
      case PlayerLost():
        _playerPresent = false;
      case PlayerFound():
        _playerPresent = true;
      case LaneChanged() || Confirmed() || CursorMoved() || Pulled():
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
