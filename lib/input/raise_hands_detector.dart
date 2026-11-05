import 'pose_types.dart';

/// Fires once when both wrists stay above the nose for [hold]; re-arms when
/// the hands come down.
///
/// All timing uses frame timestamps (the pose plugin delivers ~15 fps with
/// arrival-time stamps), never frame counts.
///
/// A frame where the nose or a wrist is missing / below [minConfidence] is
/// "doubtful": the hold timer and the fired latch survive up to [grace] after
/// the last reliable raised frame, so a one-frame landmark dropout neither
/// restarts the hold nor re-arms the detector (which would double fire). Only
/// reliably lowered hands reset immediately.
class RaiseHandsDetector {
  RaiseHandsDetector({
    this.hold = const Duration(milliseconds: 500),
    this.minConfidence = Pose.minConfidence,
    this.grace = const Duration(milliseconds: 150),
  });

  final Duration hold;

  /// Landmarks below this confidence are not trusted.
  final double minConfidence;

  /// Longest stretch without a reliable raised frame that is tolerated.
  final Duration grace;

  Duration? _since;
  Duration _lastRaised = Duration.zero;
  bool _fired = false;
  bool _doubt = false;

  void _reset() {
    _since = null;
    _doubt = false;
    _fired = false;
  }

  bool update(Pose p, Duration t) {
    final nose = _reliable(p, PoseJoint.nose);
    final left = _reliable(p, PoseJoint.leftWrist);
    final right = _reliable(p, PoseJoint.rightWrist);
    if (nose == null || left == null || right == null) {
      // Doubtful frame: tolerate a short dropout, never fire on it.
      if (_since != null) {
        _doubt = true;
        if (t - _lastRaised > grace) _reset();
      }
      return false;
    }
    final raised = left.y < nose.y && right.y < nose.y;
    if (!raised) {
      _reset();
      return false;
    }
    // Raised again after a dropout longer than the grace: restart the hold.
    // (A plain frame gap without doubtful frames is the owner's concern:
    // PoseSession resets this detector when the player is lost.)
    if (_since != null && _doubt && t - _lastRaised > grace) _reset();
    _doubt = false;
    _since ??= t;
    _lastRaised = t;
    if (!_fired && t - _since! >= hold) {
      _fired = true;
      return true;
    }
    return false;
  }

  Landmark? _reliable(Pose p, PoseJoint j) {
    final l = p.joints[j];
    return (l == null || l.confidence < minConfidence) ? null : l;
  }
}
