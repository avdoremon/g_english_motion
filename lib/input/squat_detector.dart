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
///
/// The baseline adapts, like the jump detector's: while the hips are not down,
/// a 1 s window that is still re-baselines (a step forward / back, landing
/// closer), and a slow drift (walking, below [_driftRangeTorso] per second) is
/// followed by a fast average. A fast squat moves more than that and is never
/// absorbed. Hips that stay down and still for [_healAfter] (a baseline that
/// went stale, which would otherwise latch forever) are taken as the new rest.
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

  /// 1 s window range (torso heights) below which the hips count as still.
  static const double _stillRangeTorso = 0.08;

  /// 1 s window range below which a move is a slow drift, not a squat.
  static const double _driftRangeTorso = 0.2;
  static const double _driftTauSeconds = 0.5;
  static const double _stillTauSeconds = 1.0;
  static const Duration _window = Duration(seconds: 1);
  static const Duration _windowSlack = Duration(milliseconds: 100);

  /// Drift is followed only while the last [_shortWindow] moved less than this
  /// (about 0.2 torso/s): the first part of a fast squat is not absorbed.
  static const double _driftShortRangeTorso = 0.08;
  static const Duration _shortWindow = Duration(milliseconds: 400);

  /// Still and down (or latched) this long: the baseline is stale, re-baseline.
  static const Duration _healAfter = Duration(seconds: 3);

  late double _baselineHipY = calibration.baselineHipY;
  final List<(Duration, double)> _recent = [];
  Duration? _lastT;
  Duration? _stillSince;
  Duration? _since;
  Duration _lastDown = Duration.zero;
  bool _fired = false;
  bool _doubt = false;

  /// True while a squat is held or being timed (the latch is set or the hold
  /// timer runs): the owner must not take this position as a resting one.
  bool get isDown => _fired || _since != null;

  /// Forgets the hold timer and the stillness window. The fired latch is kept.
  void reset() {
    _clearHold();
    _forgetWindow();
  }

  void _clearHold() {
    _since = null;
    _doubt = false;
  }

  void _forgetWindow() {
    _recent.clear();
    _lastT = null;
    _stillSince = null;
  }

  /// Clears the hold and the fired latch (a pose held now registers once),
  /// keeping the baseline.
  void rearm() {
    _since = null;
    _doubt = false;
    _fired = false;
    _forgetWindow();
  }

  /// Takes the pose's mid-hip y as the new standing baseline (the torso height
  /// stays the calibrated one) and clears the hold, the dropout state and the
  /// fired latch. Without a reliable mid-hip nothing changes.
  void rebaseline(Pose p) {
    final hip = p.midHipY;
    if (hip == null) return;
    _setBaseline(hip);
  }

  void _setBaseline(double hipY) {
    _baselineHipY = hipY;
    _since = null;
    _doubt = false;
    _fired = false;
    _forgetWindow();
  }

  double _recentRange(Duration t) {
    var lo = double.infinity, hi = -double.infinity;
    for (final e in _recent) {
      if (t - e.$1 > _shortWindow) continue;
      if (e.$2 < lo) lo = e.$2;
      if (e.$2 > hi) hi = e.$2;
    }
    return (hi - lo) / calibration.torsoHeight;
  }

  /// Follows a still or slowly drifting hip position (see the class doc).
  /// Only called with a reliable mid-hip y.
  void _adapt(double hipY, Duration t) {
    final prevT = _lastT;
    final dt = prevT == null ? 0.0 : (t - prevT).inMicroseconds / 1e6;
    _lastT = t;
    _recent.add((t, hipY));
    while (t - _recent.first.$1 > _window) {
      _recent.removeAt(0);
    }
    if (t - _recent.first.$1 < _window - _windowSlack) {
      _stillSince = null;
      return;
    }
    var lo = hipY, hi = hipY;
    for (final e in _recent) {
      if (e.$2 < lo) lo = e.$2;
      if (e.$2 > hi) hi = e.$2;
    }
    final range = (hi - lo) / calibration.torsoHeight;
    final drop = (hipY - _baselineHipY) / calibration.torsoHeight;
    if (range >= _stillRangeTorso) {
      _stillSince = null;
    } else {
      _stillSince ??= _recent.first.$1;
    }
    if (isDown) {
      // Down and still for long: the baseline is stale (or the child holds a
      // very long squat); take this as rest rather than latch forever.
      final still = _stillSince;
      if (still != null && t - still >= _healAfter) _setBaseline(hipY);
      return;
    }
    if (range < _stillRangeTorso) {
      if (drop.abs() >= dropTorso / 2) {
        // Persistent offset (stepped closer / farther): the whole second is
        // within a tiny range, so take it as the new rest at once.
        _baselineHipY = hipY;
      } else if (dt > 0) {
        _baselineHipY +=
            (hipY - _baselineHipY) * (dt / (_stillTauSeconds + dt));
      }
    } else if (range < _driftRangeTorso &&
        drop < dropTorso / 2 &&
        dt > 0 &&
        _recentRange(t) < _driftShortRangeTorso) {
      _baselineHipY += (hipY - _baselineHipY) * (dt / (_driftTauSeconds + dt));
    }
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
        if (t - _lastDown > grace) _clearHold();
      }
      return false;
    }
    _adapt((lh.y + rh.y) / 2, t);
    final drop = ((lh.y + rh.y) / 2 - _baselineHipY) / calibration.torsoHeight;
    if (drop <= releaseTorso) _fired = false;
    if (drop < dropTorso) {
      _clearHold();
      return false;
    }
    if (_since != null && _doubt && t - _lastDown > grace) _clearHold();
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
