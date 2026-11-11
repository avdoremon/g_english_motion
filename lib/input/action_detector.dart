import 'calibrator.dart';
import 'clap_detector.dart';
import 'jump_detector.dart';
import 'pose_types.dart';
import 'raise_hands_detector.dart';
import 'squat_detector.dart';

/// The body actions a puppySays command can name.
enum PuppyAction { jump, handsUp, clap, squat }

/// Runs the four action detectors on the same pose stream and reports every
/// action that fired on a frame (usually none; a jump with raised hands can
/// yield both [PuppyAction.jump] and [PuppyAction.handsUp] over its frames).
///
/// Each action fires once per performance and re-arms only after its pose is
/// released. For hands up that release is a reliable frame with the nose and
/// a wrist visible and a wrist not above the nose, so a hands-up held across a
/// long dropout fires once. Thresholds live in the detectors' constructors.
class ActionDetector {
  ActionDetector(this.calibration)
    : _jump = JumpDetector(calibration),
      _squat = SquatDetector(calibration);

  final Calibration calibration;
  final JumpDetector _jump;
  final SquatDetector _squat;
  final ClapDetector _clap = ClapDetector();
  RaiseHandsDetector _hands = RaiseHandsDetector();
  bool _handsFired = false;
  Duration _suppressUntil = Duration.zero;

  /// Feed one pose; returns the actions detected on this frame.
  Set<PuppyAction> update(Pose p, Duration t) {
    _releaseHands(p);
    final fired = <PuppyAction>{};
    // Standing up from a held squat is a rise of the whole body: the jump
    // baseline must not have followed the body down.
    _jump.freezeBaseline = _squat.isDown;
    if (_jump.update(p, t)) fired.add(PuppyAction.jump);
    if (_hands.update(p, t) && !_handsFired) {
      _handsFired = true;
      fired.add(PuppyAction.handsUp);
    }
    if (_clap.update(p, t)) fired.add(PuppyAction.clap);
    if (_squat.update(p, t)) fired.add(PuppyAction.squat);
    // Detectors still run (and latch) while suppressed, so a pose held through
    // the suppression window is consumed, not reported afterwards.
    return t < _suppressUntil ? <PuppyAction>{} : fired;
  }

  /// A reliable frame with a wrist not above the nose releases hands up.
  void _releaseHands(Pose p) {
    final nose = p.joints[PoseJoint.nose];
    if (nose == null || nose.confidence < Pose.minConfidence) return;
    for (final j in [PoseJoint.leftWrist, PoseJoint.rightWrist]) {
      final w = p.joints[j];
      if (w != null && w.confidence >= Pose.minConfidence && w.y >= nose.y) {
        _handsFired = false;
        return;
      }
    }
  }

  /// Forgets timers and arming state (player lost). The hands-up and squat
  /// fired latches are kept: the pose must be released before it fires again.
  void reset() {
    _hands = RaiseHandsDetector();
    _clap.reset();
    _squat.reset();
  }

  /// Re-arms hands up, clap and squat for a new round: a hands-up or squat
  /// pose that is already held registers once more (after its normal hold),
  /// instead of waiting for a release the child never makes. Jump stays an
  /// edge event and is untouched. Suppression is not changed.
  void rearm() {
    _hands = RaiseHandsDetector();
    _handsFired = false;
    _clap.reset();
    _squat.rearm();
  }

  /// Blocks every action until [t]; poses held through it are consumed.
  void suppressUntil(Duration t) {
    if (t > _suppressUntil) _suppressUntil = t;
    _jump.suppressUntil(t);
  }

  /// Takes [p] as the new resting position of the jump and squat detectors
  /// (the squat baseline becomes the pose's mid-hip y; the torso height stays
  /// the calibrated one).
  void rebaseline(Pose p) {
    _jump.rebaseline(p);
    _squat.rebaseline(p);
  }
}
