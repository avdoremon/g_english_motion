import 'dart:async';

import 'calibrator.dart';
import 'cursor_tracker.dart';
import 'game_input_event.dart';
import 'jump_detector.dart';
import 'lane_tracker.dart';
import 'one_euro_filter.dart';
import 'pose_frame_source.dart';
import 'pose_types.dart';
import 'pull_detector.dart';
import 'raise_hands_detector.dart';

/// Turns a stream of [PoseFrame] into [GameInputEvent]s for the tracked player.
///
/// Player tracking is seeded from the calibration (centre x, torso height):
/// each frame the pose minimizing |midHipX - lastX| + |torso - lastTorso| is
/// chosen; frames whose best distance exceeds [_maxTrackDistance] are ignored,
/// so bystanders (even nearer ones with a larger torso) never steal tracking.
/// The nearest pose is chosen first; if it is not reliable (e.g. low hip
/// confidence at takeoff) the frame is doubtful and nobody else is picked.
/// After [PlayerLost] tracking is re-seeded from the calibration and a wide
/// gate is used until the player is found again; while lost, a candidate must
/// also have a torso within [_maxLostTorsoDeviation] of the calibrated torso,
/// so a bystander of a different size is not adopted.
///
/// Frames whose processing keeps throwing for [_lostAfter] (frame timestamps)
/// also yield [PlayerLost]: the player cannot be followed.
///
/// Notes for the owner:
/// - [events] is a broadcast stream: subscribe synchronously after
///   construction or early events are dropped. It closes when the frame
///   stream ends or on [dispose]. Errors from the frame stream or from frame
///   processing are forwarded to it as stream errors.
/// - [PlayerLost] is frame-driven (500 ms without a valid pose, measured on
///   frame timestamps). If the source stalls and emits no frames at all, the
///   owner needs its own watchdog.
class PoseSession {
  PoseSession(
    Stream<PoseFrame> frames,
    Calibration calibration, {
    required int laneCount,
    this.confirm = ConfirmGesture.jump,
    this.minConfidence = 0.5,
    this.cursor = false,
    this.pull = false,
  }) : _laneTracker = LaneTracker(calibration, laneCount: laneCount),
       _jump = JumpDetector(calibration),
       _cursor = CursorTracker(calibration),
       _calibration = calibration,
       _seedX = calibration.centerX,
       _seedTorso = calibration.torsoHeight,
       _lastX = calibration.centerX,
       _lastTorso = calibration.torsoHeight {
    _sub = frames.listen(_onFrameSafe, onError: _onError, onDone: _onDone);
  }

  final ConfirmGesture confirm;
  final double minConfidence;

  /// Also emit [CursorMoved] (the raised wrist as a 0..1 cursor) every frame
  /// in which a reliable wrist is visible. Off for the lane modes.
  final bool cursor;

  /// Also emit [Pulled] for each "pull the rope" beat of a wrist (down, then
  /// back up). Off for the lane modes.
  final bool pull;

  static const double _maxTrackDistance = 0.25;
  static const double _maxReacquireDistance = 0.6;
  static const Duration _lostAfter = Duration(milliseconds: 500);

  /// While lost, |torso - calibrated torso| must be at most this fraction of
  /// the calibrated torso.
  static const double _maxLostTorsoDeviation = 0.35;

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
  final CursorTracker _cursor;
  final Calibration _calibration;
  late PullDetector _pull = PullDetector(_calibration);
  late RaiseHandsDetector _raise = _newRaise();
  final StreamController<GameInputEvent> _events =
      StreamController<GameInputEvent>.broadcast();
  late final StreamSubscription<PoseFrame> _sub;
  final Map<String, OneEuroFilter> _filters = {};

  // The cursor is smoothed on its output (targets are big, jitter is not).
  static const double _cursorMinCutoff = 2.0;
  static const double _cursorBeta = 5.0;
  final OneEuroFilter _cursorX = OneEuroFilter(
    minCutoff: _cursorMinCutoff,
    beta: _cursorBeta,
  );
  final OneEuroFilter _cursorY = OneEuroFilter(
    minCutoff: _cursorMinCutoff,
    beta: _cursorBeta,
  );

  final double _seedX;
  final double _seedTorso;
  double _lastX;
  double _lastTorso;
  Duration? _lastValidAt;

  /// Timestamp of the first frame of the current run of throwing frames.
  Duration? _throwingSince;
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

  RaiseHandsDetector _newRaise() =>
      RaiseHandsDetector(minConfidence: minConfidence);

  bool _reliable(Pose p) {
    for (final j in [PoseJoint.leftHip, PoseJoint.rightHip]) {
      final l = p.joints[j];
      if (l == null || l.confidence < minConfidence) return false;
    }
    return p.midHipX != null && p.torsoHeight != null;
  }

  static double? _rawHipX(Pose p) {
    final l = p.joints[PoseJoint.leftHip], r = p.joints[PoseJoint.rightHip];
    if (l == null || r == null) return null;
    return (l.x + r.x) / 2;
  }

  static double? _rawTorso(Pose p) {
    final lh = p.joints[PoseJoint.leftHip], rh = p.joints[PoseJoint.rightHip];
    final ls = p.joints[PoseJoint.leftShoulder],
        rs = p.joints[PoseJoint.rightShoulder];
    if (lh == null || rh == null || ls == null || rs == null) return null;
    return (lh.y + rh.y) / 2 - (ls.y + rs.y) / 2;
  }

  /// Nearest pose by raw position first (ignoring confidence); only then is
  /// reliability checked. An unreliable nearest pose yields null: the frame
  /// is doubtful and no other person is considered.
  Pose? _pickPlayer(List<Pose> poses) {
    Pose? best;
    var bestDist = double.infinity;
    for (final p in poses) {
      final x = _rawHipX(p), torso = _rawTorso(p);
      if (x == null || torso == null) continue;
      if (_lost &&
          (torso - _seedTorso).abs() > _maxLostTorsoDeviation * _seedTorso) {
        continue;
      }
      final d = (x - _lastX).abs() + (torso - _lastTorso).abs();
      if (d < bestDist) {
        bestDist = d;
        best = p;
      }
    }
    final gate = _lost ? _maxReacquireDistance : _maxTrackDistance;
    if (best == null || bestDist > gate) return null;
    return _reliable(best) ? best : null;
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

  void _onError(Object error, StackTrace stack) {
    if (!_disposed) _events.addError(error, stack);
  }

  void _onFrameSafe(PoseFrame f) {
    try {
      _onFrame(f);
      _throwingSince = null;
    } catch (e, st) {
      _onError(e, st);
      _onFrameFailed(f.timestamp);
    }
  }

  /// A frame could not be processed: never score through it, and after a
  /// sustained run of failures report the player as lost.
  void _onFrameFailed(Duration t) {
    _jump.suppressUntil(t + _uncertainHold);
    _raise = _newRaise();
    _pull = PullDetector(_calibration);
    _throwingSince ??= t;
    if (!_lost && t - _throwingSince! >= _lostAfter) _enterLost(t);
  }

  void _resetCursor() {
    _cursorX.reset();
    _cursorY.reset();
  }

  void _enterLost(Duration t) {
    _lost = true;
    _filters.clear();
    _resetCursor();
    _lastX = _seedX;
    _lastTorso = _seedTorso;
    _emit(PlayerLost(at: t));
  }

  void _onFrame(PoseFrame f) {
    final t = f.timestamp;
    _laneTracker.aspectRatio = f.aspectRatio;
    _cursor.aspectRatio = f.aspectRatio;
    _lastValidAt ??= t;
    final player = _pickPlayer(f.poses);

    if (player == null) {
      // Not sure who/where the player is: never score through this frame.
      _jump.suppressUntil(t + _uncertainHold);
      _raise = _newRaise();
      _pull = PullDetector(_calibration);
      if (!_lost && t - _lastValidAt! >= _lostAfter) _enterLost(t);
      return;
    }

    _lastX = player.midHipX!;
    _lastTorso = player.torsoHeight!;
    _lastValidAt = t;
    if (_lost) {
      _lost = false;
      _filters.clear();
      _resetCursor();
      _raise = _newRaise();
      _pull = PullDetector(_calibration);
      // The first frame back must not confirm anything.
      _jump.suppressUntil(t + const Duration(milliseconds: 1));
      _emit(PlayerFound(at: t));
    }

    final pose = _smooth(player, t);
    final before = _laneTracker.current;
    final lane = _laneTracker.update(pose, t);
    if (lane != before) _emit(LaneChanged(lane, at: t));

    if (cursor) {
      final c = _cursor.update(pose, t);
      if (c != null) {
        _emit(
          CursorMoved(
            _cursorX.filter(c.$1, t),
            _cursorY.filter(c.$2, t),
            at: t,
          ),
        );
      }
    }

    if (pull) {
      final hand = _pull.update(pose, t);
      if (hand != null) _emit(Pulled(hand, at: t));
    }

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
