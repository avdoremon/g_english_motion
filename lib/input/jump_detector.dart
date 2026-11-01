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

  double _baseline;
  bool _armed = true;
  bool _dropped = true;
  Duration? _lastFire;
  Duration? _stillSince;
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
    final lift = _baseline - current;
    final fireAt = threshold * calibration.torsoHeight;
    final half = fireAt / 2;
    final dt = _lastT == null ? 0.0 : (t - _lastT!).inMicroseconds / 1e6;
    _lastT = t;

    // Baseline follows slow drift, only while standing still for >= 1 s.
    if (lift.abs() < half) {
      _stillSince ??= t;
      if (t - _stillSince! >= _stillFor && dt > 0) {
        _baseline += (current - _baseline) * (dt / (_emaTauSeconds + dt));
      }
    } else {
      _stillSince = null;
    }

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
