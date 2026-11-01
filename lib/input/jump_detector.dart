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

  static const double _stillRangeRatio = 0.35; // of the firing threshold
  static const Duration _windowSlack = Duration(milliseconds: 50);

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
    // quarter of the firing threshold. A jump's takeoff/apex moves far more
    // than that within any 1 s window, so it never counts as still.
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
    if (spansWindow && hi - lo < _stillRangeRatio * fireAt) {
      if (lift.abs() >= half) {
        // Persistent offset (player stepped closer/farther): re-baseline.
        _baseline = current;
      } else if (dt > 0) {
        _baseline += (current - _baseline) * (dt / (_emaTauSeconds + dt));
      }
      _dropped = true; // at rest, so a new jump may start from here
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
