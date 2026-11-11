import 'pose_types.dart';

/// Fires once with the hand that stays alone above the nose for [hold].
///
/// Each hand has a `fired` latch: after it fires, that hand cannot fire again
/// until a reliable frame (nose and that wrist both reliable) shows that
/// wrist NOT above the nose. The other wrist's state is irrelevant to this
/// clearing. The latch survives doubtful frames, the [grace] timeout,
/// [reset] and both-hands-up frames (both up is not a lowering), so a child
/// who answers and keeps the hand up cannot auto-answer the next round after
/// a wrist dropout; the hand must be lowered and raised again. A hand that
/// never fired and becomes alone-raised fires after [hold].
///
/// Joints are anatomical (`leftWrist` is the person's own left hand);
/// [swapSides] is the single switch that mirrors the result, for sources
/// whose labels are mirrored.
///
/// Uncertain input never produces an event: both hands up, a doubtful frame
/// (nose or either wrist missing / below [minConfidence]) and an unreliable
/// other wrist all withhold the event. Timing uses frame timestamps only.
///
/// A doubtful frame tolerates up to [grace] after the last reliable
/// "raised alone" frame; beyond that the hold timer restarts (the latch does
/// not).
class HandSideDetector {
  HandSideDetector({
    this.hold = const Duration(milliseconds: 500),
    this.minConfidence = Pose.minConfidence,
    this.grace = const Duration(milliseconds: 150),
    this.swapSides = false,
  });

  final Duration hold;

  /// Landmarks below this confidence are not trusted.
  final double minConfidence;

  /// Longest stretch without a reliable raised-alone frame that is tolerated.
  final Duration grace;

  /// Report the opposite hand (mirrored source).
  final bool swapSides;

  final _left = _HandState();
  final _right = _HandState();

  /// Forget the hold timers (player lost / failed frame). The fired latches
  /// are kept: a hand that already answered must be lowered to answer again.
  void reset() {
    _left.reset();
    _right.reset();
  }

  /// Returns the hand the first time it has been raised alone for [hold];
  /// null otherwise.
  Hand? update(Pose p, Duration t) {
    final nose = _reliable(p, PoseJoint.nose);
    final left = _reliable(p, PoseJoint.leftWrist);
    final right = _reliable(p, PoseJoint.rightWrist);
    if (nose != null) {
      // A reliably lowered wrist clears its own latch, whatever the other
      // wrist is doing.
      if (left != null && left.y >= nose.y) _left.lowered();
      if (right != null && right.y >= nose.y) _right.lowered();
    }
    if (nose == null || left == null || right == null) {
      // Doubtful frame: tolerate a short dropout, never fire on it.
      _left.doubtful(t, grace);
      _right.doubtful(t, grace);
      return null;
    }
    final leftUp = left.y < nose.y;
    final rightUp = right.y < nose.y;
    final l = _left.reliable(leftUp && !rightUp, t, hold, grace);
    final r = _right.reliable(rightUp && !leftUp, t, hold, grace);
    if (l) return swapSides ? Hand.right : Hand.left;
    if (r) return swapSides ? Hand.left : Hand.right;
    return null;
  }

  Landmark? _reliable(Pose p, PoseJoint j) {
    final l = p.joints[j];
    return (l == null || l.confidence < minConfidence) ? null : l;
  }
}

class _HandState {
  Duration? since;
  Duration lastRaised = Duration.zero;

  /// Set when the hand fired; cleared only by [lowered].
  bool fired = false;
  bool doubt = false;

  /// Clears the hold timers only.
  void reset() {
    since = null;
    doubt = false;
  }

  /// Reliably not above the nose: the hand is down, the latch is released.
  void lowered() {
    reset();
    fired = false;
  }

  void doubtful(Duration t, Duration grace) {
    if (since == null) return;
    doubt = true;
    if (t - lastRaised > grace) reset();
  }

  /// A fully reliable frame; [alone] = this hand is up and the other reliably
  /// is not. Returns true when this frame completes the hold.
  bool reliable(bool alone, Duration t, Duration hold, Duration grace) {
    if (!alone) {
      reset();
      return false;
    }
    // Raised again after a dropout longer than the grace: restart the hold.
    if (since != null && doubt && t - lastRaised > grace) reset();
    doubt = false;
    since ??= t;
    lastRaised = t;
    if (!fired && t - since! >= hold) {
      fired = true;
      return true;
    }
    return false;
  }
}
