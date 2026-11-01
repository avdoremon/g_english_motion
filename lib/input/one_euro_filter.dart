import 'dart:math' as math;

/// One-Euro filter (Casiez et al. 2012). dCutoff is fixed at 1.0 Hz.
class OneEuroFilter {
  OneEuroFilter({this.minCutoff = 1.0, this.beta = 5.0});

  static const double dCutoff = 1.0;

  final double minCutoff;

  /// Speed coefficient. Default 5.0 (not 0.01): coordinates are normalized 0..1,
  /// so speeds are small and a low beta cannot meet the step-response spec.
  final double beta;

  double? _x;
  double _dx = 0;
  Duration? _t;

  static double _alpha(double cutoff, double dt) {
    final tau = 1.0 / (2 * math.pi * cutoff);
    return 1.0 / (1.0 + tau / dt);
  }

  double filter(double value, Duration t) {
    final prevX = _x, prevT = _t;
    if (prevX == null || prevT == null) {
      _x = value;
      _t = t;
      _dx = 0;
      return value;
    }
    final dt = (t - prevT).inMicroseconds / 1e6;
    if (dt <= 0) return prevX;
    final rawDx = (value - prevX) / dt;
    _dx += _alpha(dCutoff, dt) * (rawDx - _dx);
    final cutoff = minCutoff + beta * _dx.abs();
    final x = prevX + _alpha(cutoff, dt) * (value - prevX);
    _x = x;
    _t = t;
    return x;
  }

  void reset() {
    _x = null;
    _t = null;
    _dx = 0;
  }
}
