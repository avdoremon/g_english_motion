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
    double aspectRatio = PoseFrame.defaultAspectRatio,
  }) : _laneCount = laneCount < 1 ? 1 : laneCount,
       _aspect = aspectRatio > 0 ? aspectRatio : PoseFrame.defaultAspectRatio {
    // Explicit middle lane (the upper middle one for even counts): the
    // calibrated spot is the layout centre, so no float comparison is needed.
    _current = _laneCount ~/ 2;
    _baseline = _current;
  }

  /// Lane width as a fraction of the calibrated torso height.
  static const double widthPerTorso = 0.6;
  static const Duration _historySpan = Duration(milliseconds: 1500);

  final Calibration _calibration;
  final bool mirror;
  final double hysteresis;

  int _laneCount;
  double _aspect;
  late int _current;

  /// Set by [setLaneCount]: the next usable pose picks the lane directly.
  bool _resync = false;

  /// Lane that was current before the oldest retained change.
  late int _baseline;
  final List<({Duration t, int lane})> _changes = [];

  int get current => _current;

  /// Frame width / height of the latest frame. The torso height is a fraction
  /// of the frame height while x is a fraction of the width, so the lane width
  /// in x is `0.6 * torso / aspectRatio`. May change at rotation.
  double get aspectRatio => _aspect;
  set aspectRatio(double v) {
    if (v > 0) _aspect = v;
  }

  double get _width => widthPerTorso * _calibration.torsoHeight / _aspect;

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
      if (_resync) {
        _resync = false;
        next = raw;
      } else if (raw > _current) {
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
  ///
  /// Assumes [update] timestamps are non-decreasing. A query older than the
  /// retained history answers with the lane at the start of that history; a
  /// query before any update answers with the initial lane.
  int laneAt(Duration t) {
    var lane = _baseline;
    for (final c in _changes) {
      if (c.t > t) break;
      lane = c.lane;
    }
    return lane;
  }

  /// Changes the lane count. History entries are lane indices of the old
  /// layout, so they are discarded, and the next usable pose resyncs the lane
  /// to the player's actual x (without hysteresis).
  void setLaneCount(int n) {
    if (n < 1) n = 1;
    if (n == _laneCount) return;
    _laneCount = n;
    _current = _current.clamp(0, n - 1);
    _baseline = _current;
    _changes.clear();
    _resync = true;
  }
}
