import 'calibrator.dart';
import 'pose_types.dart';

/// Turns the player's raised wrist into a 0..1 cursor over the play area.
///
/// The active hand is the one whose wrist is higher; the other hand only takes
/// over when it is higher by more than [switchMargin] (so two hands at about
/// the same height do not make the cursor flip). A hand whose wrist is not
/// reliable is never used: with no reliable wrist the result is null ("no
/// cursor"), which callers must treat as "unknown", never as a miss.
///
/// Reach box (in units of the calibrated torso height): horizontally
/// `centerX +- 0.9 x torso`, vertically from `nose.y - 0.3 x torso` down to
/// the mid-hip y. x is mirrored like the lanes when [mirror] is true.
///
/// x is a fraction of the frame width while the torso is a fraction of the
/// frame height, so the horizontal reach is `0.9 x torso / aspectRatio`.
/// [aspectRatio] defaults to 1 (the literal spec formula); [PoseSession] sets
/// the real frame ratio.
class CursorTracker {
  CursorTracker(
    this._calibration, {
    this.mirror = true,
    this.switchMargin = 0.05,
    double aspectRatio = 1.0,
  }) : _aspect = aspectRatio > 0 ? aspectRatio : 1.0;

  static const double reachX = 0.9;
  static const double topAboveNose = 0.3;

  final Calibration _calibration;
  final bool mirror;
  final double switchMargin;

  double _aspect;
  Hand? _active;

  set aspectRatio(double v) {
    if (v > 0) _aspect = v;
  }

  /// The hand currently driving the cursor (null until one was seen).
  Hand? get activeHand => _active;

  Landmark? _wrist(Pose p, PoseJoint j) {
    final l = p.joints[j];
    if (l == null || l.confidence < Pose.minConfidence) return null;
    return l;
  }

  (double, double)? update(Pose p, Duration t) {
    final left = _wrist(p, PoseJoint.leftWrist);
    final right = _wrist(p, PoseJoint.rightWrist);
    if (left == null && right == null) return null;
    final Hand hand;
    if (left == null) {
      hand = Hand.right;
    } else if (right == null) {
      hand = Hand.left;
    } else {
      final active = _active;
      if (active == null) {
        hand = left.y < right.y ? Hand.left : Hand.right;
      } else {
        final cur = active == Hand.left ? left : right;
        final other = active == Hand.left ? right : left;
        hand = cur.y - other.y > switchMargin
            ? (active == Hand.left ? Hand.right : Hand.left)
            : active;
      }
    }
    _active = hand;
    final w = hand == Hand.left ? left! : right!;

    final nose = _wrist(p, PoseJoint.nose);
    final hipY = p.midHipY;
    if (nose == null || hipY == null) return null;
    final torso = _calibration.torsoHeight;
    final top = nose.y - topAboveNose * torso;
    if (hipY <= top) return null;
    final half = reachX * torso / _aspect;
    final center = mirror ? 1 - _calibration.centerX : _calibration.centerX;
    final wx = mirror ? 1 - w.x : w.x;
    final x = ((wx - (center - half)) / (2 * half)).clamp(0.0, 1.0);
    final y = ((w.y - top) / (hipY - top)).clamp(0.0, 1.0);
    return (x, y);
  }
}
