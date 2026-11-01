import '../input/game_input_event.dart';

enum RoundResult { correct, wrong, timeout }

/// One question round. [start] is called once the question has been read
/// aloud; before that the clock is stopped and every [Confirmed] is ignored.
/// After [PlayerLost] the clock stops and [Confirmed] is ignored until
/// [PlayerFound]. Once [result] is set it never changes.
///
/// Ordering contract: within one frame the caller applies [onEvent] for the
/// frame's input events BEFORE [tick], so an answer given on the last frame
/// is graded, not timed out. [tick] ignores a [Duration] of zero or less;
/// a tick larger than [remaining] clamps it to zero and ends the round with
/// [RoundResult.timeout].
abstract class Round {
  void start();
  void onEvent(GameInputEvent e);
  void tick(Duration dt);
  RoundResult? get result;
  int? get chosenIndex;
  Duration get remaining;
  bool get clockRunning;
}
