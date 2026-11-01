import 'calibrator.dart';
import 'pose_types.dart';

/// Maps the player's mid-hip x to a discrete lane, with hysteresis and a
/// short history so callers can ask which lane was current at a past time.
class LaneTracker {
  LaneTracker(
    this._calibration, {
    required int laneCount,
    this.mirror = true,
    this.hysteresis = 0.1,
  }) : _laneCount = laneCount < 1 ? 1 : laneCount {
    _current = _rawLane(_center);
    _baseline = _current;
  }

  /// Lane width as a fraction of the calibrated torso height.
  static const double widthPerTorso = 0.6;
  static const Duration _historySpan = Duration(milliseconds: 1500);

  final Calibration _calibration;
  final bool mirror;
  final double hysteresis;

  int _laneCount;
  late int _current;

  /// Lane that was current before the oldest retained change.
  late int _baseline;
  final List<({Duration t, int lane})> _changes = [];

  int get current => _current;

  double get _width => widthPerTorso * _calibration.torsoHeight;

  /// Lane layout is symmetric around the (possibly mirrored) centre.
  double get _center =>
      mirror ? 1 - _calibration.centerX : _calibration.centerX;

  int _rawLane(double x) {
    final left = _center - _laneCount * _width / 2;
    final idx = ((x - left) / _width).floor();
    return idx.clamp(0, _laneCount - 1);
  }

  int update(Pose p, Duration t) {
    final hip = p.midHipX;
    if (hip != null) {
      final x = mirror ? 1 - hip : hip;
      final h = hysteresis * _width;
      final raw = _rawLane(x);
      var next = _current;
      if (raw > _current) {
        final shifted = _rawLane(x - h);
        if (shifted > _current) next = shifted;
      } else if (raw < _current) {
        final shifted = _rawLane(x + h);
        if (shifted < _current) next = shifted;
      }
      if (next != _current) {
        _current = next;
        _changes.add((t: t, lane: next));
      }
    }
    _prune(t);
    return _current;
  }

  void _prune(Duration now) {
    final cutoff = now - _historySpan;
    while (_changes.isNotEmpty && _changes.first.t < cutoff) {
      _baseline = _changes.removeAt(0).lane;
    }
  }

  /// Lane that was current at time [t] (history of the last ~1.5 s).
  int laneAt(Duration t) {
    var lane = _baseline;
    for (final c in _changes) {
      if (c.t > t) break;
      lane = c.lane;
    }
    return lane;
  }

  void setLaneCount(int n) {
    if (n < 1) n = 1;
    _laneCount = n;
    int clamp(int l) => l.clamp(0, n - 1);
    _current = clamp(_current);
    _baseline = clamp(_baseline);
    for (var i = 0; i < _changes.length; i++) {
      _changes[i] = (t: _changes[i].t, lane: clamp(_changes[i].lane));
    }
  }
}
