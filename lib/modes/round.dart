import '../input/game_input_event.dart';

enum RoundResult { correct, wrong, timeout }

/// One question round. [start] is called once the question has been read
/// aloud; before that the clock is stopped and every [Confirmed] is ignored.
/// After [PlayerLost] the clock stops and [Confirmed] is ignored until
/// [PlayerFound]. Once [result] is set it never changes.
abstract class Round {
  void start();
  void onEvent(GameInputEvent e);
  void tick(Duration dt);
  RoundResult? get result;
  int? get chosenIndex;
  Duration get remaining;
  bool get clockRunning;
}
