import 'calibrator.dart';
import 'pose_types.dart';

/// Detects the "pull the rope" beat: a wrist goes down by at least
/// [minTravel] x torso and then comes back up by at least half of that.
///
/// Each hand is followed on its own and a beat is reported on the frame the
/// hand has come back up far enough (the returned hand is the one that just
/// finished a beat). Both hands finishing on the same frame are reported on
/// consecutive calls. A wrist that is missing / below the pose confidence is
/// skipped; slow movements (a hand lowered or raised over more than
/// [window]) are not beats.
class PullDetector {
  PullDetector(
    this.calibration, {
    this.minTravel = 0.4,
    this.window = const Duration(milliseconds: 1500),
  });

  final Calibration calibration;

  /// Down travel needed, in torso heights (the way back up needs half).
  final double minTravel;

  /// A beat's down movement, and the stay at the bottom, must fit in this.
  final Duration window;

  final Map<Hand, _Wrist> _wrists = {Hand.left: _Wrist(), Hand.right: _Wrist()};
  final List<Hand> _queue = [];

  Hand? update(Pose p, Duration t) {
    final need = minTravel * calibration.torsoHeight;
    for (final hand in Hand.values) {
      final joint = hand == Hand.left
          ? PoseJoint.leftWrist
          : PoseJoint.rightWrist;
      final w = p.joints[joint];
      if (w == null || w.confidence < Pose.minConfidence) continue;
      if (_wrists[hand]!.step(w.y, t, need, window)) _queue.add(hand);
    }
    return _queue.isEmpty ? null : _queue.removeAt(0);
  }
}

class _Wrist {
  bool _down = false;

  /// While up: the highest point seen (smallest y) and when. While down: the
  /// lowest point seen and when.
  double _ref = 0;
  Duration _refAt = Duration.zero;
  bool _seen = false;

  void _anchor(double y, Duration t) {
    _down = false;
    _ref = y;
    _refAt = t;
  }

  /// True when this sample completes a beat.
  bool step(double y, Duration t, double need, Duration window) {
    if (!_seen) {
      _seen = true;
      _anchor(y, t);
      return false;
    }
    if (!_down) {
      if (y <= _ref) {
        _ref = y;
        _refAt = t;
      } else if (t - _refAt > window) {
        // Drifted down slowly: not a beat, follow the hand.
        _anchor(y, t);
      } else if (y - _ref >= need) {
        _down = true;
        _ref = y;
        _refAt = t;
      }
      return false;
    }
    if (y >= _ref) {
      _ref = y;
      _refAt = t;
      return false;
    }
    if (_ref - y >= need / 2) {
      _anchor(y, t);
      return true;
    }
    if (t - _refAt > window) _anchor(y, t); // stalled at the bottom
    return false;
  }
}
