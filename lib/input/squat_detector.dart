import 'calibrator.dart';
import 'pose_types.dart';

/// Fires once when the mid-hip y stays at least [dropTorso] torso heights
/// below the calibrated baseline for [hold]; re-arms when the hips are back
/// within [releaseTorso] of the baseline.
///
/// The fired latch is cleared only by a reliable frame showing the hips back
/// up; doubtful frames (hips missing / below [minConfidence]), the [grace]
/// timeout and [reset] never clear it, so a child who stays down across a
/// landmark dropout does not fire again. A doubtful frame tolerates up to
/// [grace] after the last reliable squatting frame; beyond that the hold
/// restarts. Timing uses frame timestamps only.
class SquatDetector {
  SquatDetector(
    this.calibration, {
    this.dropTorso = 0.25,
    this.hold = const Duration(milliseconds: 300),
    this.releaseTorso = 0.10,
    this.grace = const Duration(milliseconds: 150),
    this.minConfidence = Pose.minConfidence,
  });

  final Calibration calibration;

  /// Hip drop, in torso heights, that counts as a squat.
  final double dropTorso;
  final Duration hold;

  /// Hip drop, in torso heights, below which the squat is released.
  final double releaseTorso;

  /// Longest stretch without a reliable squatting frame that is tolerated.
  final Duration grace;

  /// Landmarks below this confidence are not trusted.
  final double minConfidence;

  Duration? _since;
  Duration _lastDown = Duration.zero;
  bool _fired = false;
  bool _doubt = false;

  /// Forgets the hold timer. The fired latch is kept.
  void reset() {
    _since = null;
    _doubt = false;
  }

  /// Feed one pose; returns true on the frame a squat is detected.
  bool update(Pose p, Duration t) {
    final lh = p.joints[PoseJoint.leftHip];
    final rh = p.joints[PoseJoint.rightHip];
    if (lh == null ||
        rh == null ||
        lh.confidence < minConfidence ||
        rh.confidence < minConfidence) {
      if (_since != null) {
        _doubt = true;
        if (t - _lastDown > grace) reset();
      }
      return false;
    }
    final drop =
        ((lh.y + rh.y) / 2 - calibration.baselineHipY) /
        calibration.torsoHeight;
    if (drop <= releaseTorso) _fired = false;
    if (drop < dropTorso) {
      reset();
      return false;
    }
    if (_since != null && _doubt && t - _lastDown > grace) reset();
    _doubt = false;
    _since ??= t;
    _lastDown = t;
    if (!_fired && t - _since! >= hold) {
      _fired = true;
      return true;
    }
    return false;
  }
}
