/// What the UI shell needs from a level session.
abstract interface class PausableSession {
  void pause();
  void resume();
}
