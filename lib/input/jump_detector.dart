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

  static const double _stillSpeed = 0.12; // ~0.004 per frame at 30 fps
  static const double _speedTauSeconds = 0.05;

  double _baseline;
  double _speed = 0;
  double? _lastY;
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
    var lift = _baseline - current;
    final fireAt = threshold * calibration.torsoHeight;
    final half = fireAt / 2;
    final prevT = _lastT, prevY = _lastY;
    final dt = prevT == null ? 0.0 : (t - prevT).inMicroseconds / 1e6;
    _lastT = t;
    _lastY = current;

    // Velocity-based stillness: low-passed |dy/dt| below the limit for >= 1 s.
    // A jump apex passes through ~0 velocity only momentarily, so it never
    // lasts 1 s; a slow drift or a player settling at a new spot does.
    if (prevY != null && dt > 0) {
      final raw = (current - prevY).abs() / dt;
      _speed += (raw - _speed) * (dt / (_speedTauSeconds + dt));
    }
    if (_speed < _stillSpeed) {
      _stillSince ??= t;
      if (t - _stillSince! >= _stillFor && dt > 0) {
        if (lift.abs() >= half) {
          // Persistent offset (player stepped closer/farther): re-baseline.
          _baseline = current;
        } else {
          _baseline += (current - _baseline) * (dt / (_emaTauSeconds + dt));
        }
        _dropped = true; // at rest, so a new jump may start from here
      }
    } else {
      _stillSince = null;
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
