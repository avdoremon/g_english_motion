import 'calibrator.dart';
import 'pose_types.dart';

/// Detects a jump from the mean lift of (mid-hip, mid-shoulder) against an
/// adaptive baseline. y points down, so lift = baseline - current.
class JumpDetector {
  JumpDetector(
    this.calibration, {
    this.threshold = 0.12,
    this.debounce = const Duration(milliseconds: 600),
  }) : _baseline =
           (calibration.baselineHipY + calibration.baselineShoulderY) / 2;

  final Calibration calibration;

  /// Fraction of torso height the body must rise to count as a jump.
  final double threshold;
  final Duration debounce;

  static const Duration _stillFor = Duration(seconds: 1);
  static const double _emaTauSeconds = 1.0;

  /// 1 s window range below this fraction of the firing threshold = still:
  /// full adaptation (EMA tau 1 s, or an immediate re-baseline on a step).
  static const double _stillRangeRatio = 0.35;

  /// 1 s window range below this fraction = slow drift (e.g. a child walking
  /// slowly toward the camera, 0.0126..0.025 per second at the default
  /// threshold). The baseline follows with a faster EMA, but only while the
  /// lift is below half the threshold, so a real jump's rise is never
  /// absorbed (a jump moves several times the threshold within a second).
  static const double _driftRangeRatio = 0.7;
  static const double _driftTauSeconds = 0.5;

  /// The 1 s window is judged spanned when its oldest sample is at least
  /// 1 s - slack old. Must exceed the longest expected frame interval
  /// (the pose plugin delivers ~15 fps, i.e. ~67 ms) so the check does not
  /// flicker with frame timing.
  static const Duration _windowSlack = Duration(milliseconds: 100);

  double _baseline;
  final List<(Duration, double)> _recent = [];
  bool _armed = true;
  bool _dropped = true;
  Duration? _lastFire;
  Duration? _lastT;
  Duration _suppressUntil = Duration.zero;

  /// Blocks firing until [t] (inclusive of earlier timestamps only).
  void suppressUntil(Duration t) {
    if (t > _suppressUntil) _suppressUntil = t;
  }

  /// Feed one pose; returns true on the frame a jump is detected.
  bool update(Pose p, Duration t) {
    final hip = p.midHipY, shoulder = p.midShoulderY;
    if (hip == null || shoulder == null) return false;
    final current = (hip + shoulder) / 2;
    var lift = _baseline - current;
    final fireAt = threshold * calibration.torsoHeight;
    final half = fireAt / 2;
    final prevT = _lastT;
    final dt = prevT == null ? 0.0 : (t - prevT).inMicroseconds / 1e6;
    _lastT = t;

    // Range-based stillness (independent of frame rate and jitter): over the
    // last ~1 s the peak-to-peak y of the mean (hip, shoulder) stays below a
    // 0.35 x the firing threshold. A jump's takeoff/apex moves far more than
    // that within any 1 s window, so it never counts as still. All windows are
    // timestamp-based, so the behaviour does not depend on the frame rate.
    _recent.add((t, current));
    while (t - _recent.first.$1 > _stillFor) {
      _recent.removeAt(0);
    }
    var lo = current, hi = current;
    for (final e in _recent) {
      if (e.$2 < lo) lo = e.$2;
      if (e.$2 > hi) hi = e.$2;
    }
    final spansWindow = t - _recent.first.$1 >= _stillFor - _windowSlack;
    final range = hi - lo;
    if (spansWindow && range < _stillRangeRatio * fireAt) {
      if (lift.abs() >= half) {
        // Persistent offset (player stepped closer/farther): re-baseline.
        _baseline = current;
      } else if (dt > 0) {
        _baseline += (current - _baseline) * (dt / (_emaTauSeconds + dt));
      }
      _dropped = true; // at rest, so a new jump may start from here
    } else if (spansWindow &&
        range < _driftRangeRatio * fireAt &&
        lift.abs() < half &&
        dt > 0) {
      // Slow drift: track it with a faster EMA (sub-half lift only).
      _baseline += (current - _baseline) * (dt / (_driftTauSeconds + dt));
    }

    lift = _baseline - current;

    // Re-arm needs both: having dropped below half threshold since the last
    // fire, and the debounce having elapsed.
    if (lift < half) _dropped = true;
    if (!_armed) {
      final last = _lastFire;
      final cooled = last == null || t - last >= debounce;
      if (_dropped && cooled) _armed = true;
    }
    if (_armed && lift >= fireAt) {
      _armed = false;
      _dropped = false;
      if (t < _suppressUntil) return false; // consumed, not reported
      _lastFire = t;
      return true;
    }
    return false;
  }
}
