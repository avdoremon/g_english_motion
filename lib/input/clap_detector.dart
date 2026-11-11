import 'pose_types.dart';

/// Fires once when the hands come together: both wrists were at least
/// [apartShoulderWidths] shoulder widths apart (x distance) while both above
/// the mid-hip y (arms hanging down are about 1.0-1.4 shoulder widths apart
/// below the hips, so they never arm it) and, within [window], end up within [togetherShoulderWidths] of each other, at about
/// the same height ([maxDyTorso] torso heights) and above the mid-hip y.
///
/// The shoulder width and the torso height are read from the current frame,
/// so the detector needs no calibration. After a clap it needs the wrists to
/// be apart again (a held clap fires once), and further
/// claps are ignored for [debounce]. A doubtful frame (a needed joint missing
/// or below [minConfidence]) never fires and changes no state, so a short
/// dropout between "apart" and "together" simply ages the window.
///
/// Timing uses frame timestamps only.
class ClapDetector {
  ClapDetector({
    this.window = const Duration(milliseconds: 800),
    this.debounce = const Duration(milliseconds: 800),
    this.apartShoulderWidths = 1.5,
    this.togetherShoulderWidths = 0.25,
    this.maxDyTorso = 0.25,
    this.minConfidence = Pose.minConfidence,
  });

  /// Longest time from the last "apart" frame to the "together" frame.
  final Duration window;

  /// Minimum time between two fired claps.
  final Duration debounce;

  /// Wrist x distance (in shoulder widths) that counts as "apart" (with both
  /// wrists above the mid-hip y).
  final double apartShoulderWidths;

  /// Wrist x distance (in shoulder widths) that counts as "together".
  final double togetherShoulderWidths;

  /// Largest wrist height difference, in torso heights, of a clap.
  final double maxDyTorso;

  /// Landmarks below this confidence are not trusted.
  final double minConfidence;

  /// Frames whose shoulder x distance is below this are doubtful (a person
  /// turned sideways or a bad detection): no width to measure against.
  static const double minShoulderWidth = 0.05;

  Duration? _apartAt;
  Duration? _lastFire;

  /// Forgets the apart state and the latch.
  void reset() {
    _apartAt = null;
    _lastFire = null;
  }

  /// Feed one pose; returns true on the frame a clap is detected.
  bool update(Pose p, Duration t) {
    final lw = _reliable(p, PoseJoint.leftWrist);
    final rw = _reliable(p, PoseJoint.rightWrist);
    final ls = _reliable(p, PoseJoint.leftShoulder);
    final rs = _reliable(p, PoseJoint.rightShoulder);
    final lh = _reliable(p, PoseJoint.leftHip);
    final rh = _reliable(p, PoseJoint.rightHip);
    if (lw == null ||
        rw == null ||
        ls == null ||
        rs == null ||
        lh == null ||
        rh == null) {
      return false; // doubtful
    }
    final shoulderWidth = (ls.x - rs.x).abs();
    final hipY = (lh.y + rh.y) / 2;
    final torso = hipY - (ls.y + rs.y) / 2;
    if (shoulderWidth < minShoulderWidth || torso <= 0) return false;

    final dx = (lw.x - rw.x).abs();
    final above = lw.y < hipY && rw.y < hipY;
    if (dx >= apartShoulderWidths * shoulderWidth && above) {
      _apartAt = t;
      return false;
    }
    final apartAt = _apartAt;
    if (apartAt == null || t - apartAt > window) return false;
    final together =
        dx <= togetherShoulderWidths * shoulderWidth &&
        (lw.y - rw.y).abs() <= maxDyTorso * torso &&
        above;
    if (!together) return false;
    _apartAt = null; // consumed: needs a new "apart" before the next clap
    final last = _lastFire;
    if (last != null && t - last < debounce) return false;
    _lastFire = t;
    return true;
  }

  Landmark? _reliable(Pose p, PoseJoint j) {
    final l = p.joints[j];
    return (l == null || l.confidence < minConfidence) ? null : l;
  }
}
