import 'dart:async';

import 'calibrator.dart';
import 'game_input_event.dart';
import 'jump_detector.dart';
import 'lane_tracker.dart';
import 'one_euro_filter.dart';
import 'pose_frame_source.dart';
import 'pose_types.dart';
import 'raise_hands_detector.dart';

/// Turns a stream of [PoseFrame] into [GameInputEvent]s for the tracked player.
///
/// Player tracking is seeded from the calibration (centre x, torso height):
/// each frame the pose minimizing |midHipX - lastX| + |torso - lastTorso| is
/// chosen; frames whose best distance exceeds [_maxTrackDistance] are ignored,
/// so bystanders (even nearer ones with a larger torso) never steal tracking.
class PoseSession {
  PoseSession(
    Stream<PoseFrame> frames,
    Calibration calibration, {
    required int laneCount,
    this.confirm = ConfirmGesture.jump,
    this.minConfidence = 0.5,
  }) : _laneTracker = LaneTracker(calibration, laneCount: laneCount),
       _jump = JumpDetector(calibration),
       _lastX = calibration.centerX,
       _lastTorso = calibration.torsoHeight {
    _sub = frames.listen(_onFrame, onDone: _onDone);
  }

  final ConfirmGesture confirm;
  final double minConfidence;

  static const double _maxTrackDistance = 0.25;
  static const Duration _lostAfter = Duration(milliseconds: 500);

  /// Look-back from the threshold-crossing frame to (approximately) takeoff.
  static const Duration _takeoffLookback = Duration(milliseconds: 250);

  /// After an unreliable frame, a jump crossing is not trusted for this long.
  static const Duration _uncertainHold = Duration(milliseconds: 100);

  // Smoothing: responsive enough that the threshold crossing is not delayed
  // by more than a frame or two, yet damps landmark jitter.
  static const double _minCutoff = 4.0;
  static const double _beta = 30.0;

  static const _smoothed = [
    PoseJoint.leftHip,
    PoseJoint.rightHip,
    PoseJoint.leftShoulder,
    PoseJoint.rightShoulder,
  ];

  final LaneTracker _laneTracker;
  final JumpDetector _jump;
  final RaiseHandsDetector _raise = RaiseHandsDetector();
  final StreamController<GameInputEvent> _events =
      StreamController<GameInputEvent>.broadcast();
  late final StreamSubscription<PoseFrame> _sub;
  final Map<String, OneEuroFilter> _filters = {};

  double _lastX;
  double _lastTorso;
  Duration? _lastValidAt;
  bool _lost = false;
  Duration _suppressConfirmUntil = Duration.zero;
  bool _disposed = false;

  Stream<GameInputEvent> get events => _events.stream;

  int get currentLane => _laneTracker.current;

  void setLaneCount(int n) => _laneTracker.setLaneCount(n);

  void suppressConfirmUntil(Duration t) {
    if (t > _suppressConfirmUntil) _suppressConfirmUntil = t;
    _jump.suppressUntil(t);
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _sub.cancel();
    await _events.close();
  }

  void _onDone() {
    if (!_disposed) dispose();
  }

  bool _reliable(Pose p) {
    for (final j in [PoseJoint.leftHip, PoseJoint.rightHip]) {
      final l = p.joints[j];
      if (l == null || l.confidence < minConfidence) return false;
    }
    return p.midHipX != null && p.torsoHeight != null;
  }

  Pose? _pickPlayer(List<Pose> poses) {
    Pose? best;
    var bestDist = double.infinity;
    for (final p in poses) {
      if (!_reliable(p)) continue;
      final d =
          (p.midHipX! - _lastX).abs() + (p.torsoHeight! - _lastTorso).abs();
      if (d < bestDist) {
        bestDist = d;
        best = p;
      }
    }
    if (best == null || bestDist > _maxTrackDistance) return null;
    return best;
  }

  Pose _smooth(Pose p, Duration t) {
    final joints = Map<PoseJoint, Landmark>.of(p.joints);
    for (final j in _smoothed) {
      final l = joints[j];
      if (l == null) continue;
      final fx = _filters.putIfAbsent(
        '${j.name}.x',
        () => OneEuroFilter(minCutoff: _minCutoff, beta: _beta),
      );
      final fy = _filters.putIfAbsent(
        '${j.name}.y',
        () => OneEuroFilter(minCutoff: _minCutoff, beta: _beta),
      );
      joints[j] = Landmark(fx.filter(l.x, t), fy.filter(l.y, t), l.confidence);
    }
    return Pose(joints);
  }

  void _emit(GameInputEvent e) {
    if (!_disposed) _events.add(e);
  }

  void _onFrame(PoseFrame f) {
    final t = f.timestamp;
    _lastValidAt ??= t;
    final player = _pickPlayer(f.poses);

    if (player == null) {
      // Not sure who/where the player is: never score through this frame.
      _jump.suppressUntil(t + _uncertainHold);
      if (!_lost && t - _lastValidAt! >= _lostAfter) {
        _lost = true;
        _filters.clear();
        _emit(PlayerLost(at: t));
      }
      return;
    }

    _lastX = player.midHipX!;
    _lastTorso = player.torsoHeight!;
    _lastValidAt = t;
    if (_lost) {
      _lost = false;
      _filters.clear();
      // The first frame back must not confirm anything.
      _jump.suppressUntil(t + const Duration(milliseconds: 1));
      _emit(PlayerFound(at: t));
    }

    final pose = _smooth(player, t);
    final before = _laneTracker.current;
    final lane = _laneTracker.update(pose, t);
    if (lane != before) _emit(LaneChanged(lane, at: t));

    final bool fired;
    switch (confirm) {
      case ConfirmGesture.jump:
        fired = _jump.update(pose, t);
      case ConfirmGesture.raiseHands:
        fired = _raise.update(pose, t);
    }
    if (fired && t >= _suppressConfirmUntil) {
      _emit(Confirmed(_laneTracker.laneAt(t - _takeoffLookback), at: t));
    }
  }
}
