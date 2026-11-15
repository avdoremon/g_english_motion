import 'action_detector.dart';
import 'pose_types.dart';

sealed class GameInputEvent {
  const GameInputEvent({required this.at});

  final Duration at;
}

class LaneChanged extends GameInputEvent {
  const LaneChanged(this.lane, {required super.at});
  final int lane;
}

class Confirmed extends GameInputEvent {
  const Confirmed(this.lane, {required super.at});
  final int lane;
}

class CursorMoved extends GameInputEvent {
  const CursorMoved(this.x, this.y, {required super.at});
  final double x;
  final double y;
}

class Pulled extends GameInputEvent {
  const Pulled(this.hand, {required super.at});
  final Hand hand;
}

class HandRaised extends GameInputEvent {
  const HandRaised(this.hand, {required super.at});
  final Hand hand;
}

/// The player performed a body [action] (puppySays); see [ActionDetector].
class ActionPerformed extends GameInputEvent {
  const ActionPerformed(this.action, {required super.at});
  final PuppyAction action;
}

class PlayerLost extends GameInputEvent {
  const PlayerLost({required super.at});
}

class PlayerFound extends GameInputEvent {
  const PlayerFound({required super.at});
}
