import 'pose_types.dart';

/// Fires once when both wrists stay above the nose for [hold]; re-arms when
/// the hands come down.
class RaiseHandsDetector {
  RaiseHandsDetector({this.hold = const Duration(milliseconds: 500)});

  final Duration hold;

  Duration? _since;
  bool _fired = false;

  bool update(Pose p, Duration t) {
    final nose = _reliable(p, PoseJoint.nose);
    final left = _reliable(p, PoseJoint.leftWrist);
    final right = _reliable(p, PoseJoint.rightWrist);
    final raised =
        nose != null &&
        left != null &&
        right != null &&
        left.y < nose.y &&
        right.y < nose.y;
    if (!raised) {
      _since = null;
      _fired = false;
      return false;
    }
    _since ??= t;
    if (!_fired && t - _since! >= hold) {
      _fired = true;
      return true;
    }
    return false;
  }

  static Landmark? _reliable(Pose p, PoseJoint j) {
    final l = p.joints[j];
    return (l == null || l.confidence < Pose.minConfidence) ? null : l;
  }
}
