import 'pose_types.dart';

class Calibration {
  const Calibration({
    required this.torsoHeight,
    required this.centerX,
    required this.baselineHipY,
    required this.baselineShoulderY,
  });

  final double torsoHeight;
  final double centerX;
  final double baselineHipY;
  final double baselineShoulderY;
}

enum CalibrationIssue { noPerson, notStill, tooClose, notCentered }

class CalibrationProgress {
  const CalibrationProgress({
    required this.progress,
    this.result,
    this.issue,
    this.selectedPoseIndex,
  });

  /// 0..1 fraction of the hold completed.
  final double progress;
  final Calibration? result;
  final CalibrationIssue? issue;
  final int? selectedPoseIndex;
}

/// One person followed across frames (keyed by hip position, not by the
/// pose's index in the list, whose order is not stable).
class _Track {
  _Track(Pose p, this.index) : lastX = p.midHipX!, lastY = p.midHipY! {
    samples.add(p);
  }

  final List<Pose> samples = [];
  double lastX, lastY;

  /// Index of the latest matched pose in its frame.
  int index;

  void add(Pose p, int i) {
    samples.add(p);
    lastX = p.midHipX!;
    lastY = p.midHipY!;
    index = i;
  }
}

/// Averages ~[hold] of frames, picks the still pose closest to the center.
///
/// Tolerances (landmark jitter and kids' stance are noisy):
/// - still means the mid-hip y moved by less than [stillRatio] x torso
///   (peak-to-peak) over the hold;
/// - a stretch of up to [maxBadGap] (timestamp-based, so independent of the
///   frame rate) without a usable person is absorbed (it counts as time but
///   gives no samples); a longer one resets;
/// - at least [minSamples] usable frames are required besides the time span,
///   so a long frame gap cannot calibrate from two frames.
class Calibrator {
  Calibrator({this.hold = const Duration(seconds: 2)});

  final Duration hold;

  /// Frame-interval slack so that N frames spanning (N-1) intervals count as
  /// a full hold (about one interval at the plugin's ~15 fps is 67 ms, so
  /// this is half of that; the hold is always completed by timestamps).
  static const Duration _frameSlack = Duration(milliseconds: 40);

  /// Allowed peak-to-peak hip-y movement over the hold, in torso heights.
  static const double stillRatio = 0.08;

  /// Longest stretch (by timestamp) without a usable person that does not
  /// reset the hold.
  static const Duration maxBadGap = Duration(milliseconds: 250);

  /// Minimum number of usable frames in the hold, besides the time span.
  static const int minSamples = 8;

  /// Largest |dx|+|dy| hip move between frames for the same person.
  static const double _maxTrackJump = 0.15;
  static const double _maxCenterOffset = 0.2;
  static const double _minNoseY = 0.08;
  static const double _minCoverage = 0.8;

  Duration? _start;
  int _frames = 0;
  int _goodFrames = 0;
  Duration _lastGoodAt = Duration.zero;
  final List<_Track> _tracks = [];

  void _reset() {
    _start = null;
    _frames = 0;
    _goodFrames = 0;
    _tracks.clear();
  }

  CalibrationProgress _fail(CalibrationIssue issue) {
    _reset();
    return CalibrationProgress(progress: 0, issue: issue);
  }

  static bool _isTooClose(Pose p) {
    bool ok(PoseJoint j) {
      final l = p.joints[j];
      return l != null && l.confidence >= Pose.minConfidence;
    }

    if (!ok(PoseJoint.nose) ||
        !ok(PoseJoint.leftKnee) ||
        !ok(PoseJoint.rightKnee)) {
      return true;
    }
    return p.joints[PoseJoint.nose]!.y < _minNoseY;
  }

  /// Adds this frame's usable poses to the tracks by nearest hip position.
  void _assign(Map<int, Pose> usable) {
    final pairs = <({double d, int pose, _Track track})>[];
    for (final e in usable.entries) {
      for (final t in _tracks) {
        final d =
            (e.value.midHipX! - t.lastX).abs() +
            (e.value.midHipY! - t.lastY).abs();
        if (d <= _maxTrackJump) pairs.add((d: d, pose: e.key, track: t));
      }
    }
    pairs.sort((a, b) => a.d.compareTo(b.d));
    final usedPoses = <int>{};
    final usedTracks = <_Track>{};
    for (final pr in pairs) {
      if (usedPoses.contains(pr.pose) || usedTracks.contains(pr.track)) {
        continue;
      }
      usedPoses.add(pr.pose);
      usedTracks.add(pr.track);
      pr.track.add(usable[pr.pose]!, pr.pose);
    }
    for (final e in usable.entries) {
      if (!usedPoses.contains(e.key)) _tracks.add(_Track(e.value, e.key));
    }
  }

  CalibrationProgress add(PoseFrame f) {
    final usable = <int, Pose>{};
    var anyPerson = false;
    for (var i = 0; i < f.poses.length; i++) {
      final p = f.poses[i];
      final torso = p.torsoHeight;
      if (p.midHipY == null ||
          p.midHipX == null ||
          torso == null ||
          torso <= 0) {
        continue;
      }
      anyPerson = true;
      if (!_isTooClose(p)) usable[i] = p;
    }

    if (usable.isEmpty) {
      final issue = anyPerson
          ? CalibrationIssue.tooClose
          : CalibrationIssue.noPerson;
      if (_start == null || f.timestamp - _lastGoodAt > maxBadGap) {
        return _fail(issue);
      }
      _frames++;
    } else {
      _lastGoodAt = f.timestamp;
      _goodFrames++;
      _start ??= f.timestamp;
      _frames++;
      _assign(usable);
    }

    final elapsed = f.timestamp - _start! + _frameSlack;
    final progress = (elapsed.inMicroseconds / hold.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    if (progress < 1.0) return CalibrationProgress(progress: progress);
    if (_goodFrames < minSamples) {
      // Time is up but there are too few samples: keep collecting.
      return const CalibrationProgress(progress: 0.99);
    }
    return _finish();
  }

  CalibrationProgress _finish() {
    _Track? bestTrack;
    double bestOffset = double.infinity;
    Calibration? best;
    for (final track in _tracks) {
      final s = track.samples;
      if (s.length < _minCoverage * _frames) continue;
      final n = s.length;
      final hips = [for (final p in s) p.midHipY!];
      final shoulders = [for (final p in s) p.midShoulderY!];
      final torso =
          [for (final p in s) p.torsoHeight!].reduce((a, b) => a + b) / n;
      final minHip = hips.reduce((a, b) => a < b ? a : b);
      final maxHip = hips.reduce((a, b) => a > b ? a : b);
      if (maxHip - minHip >= stillRatio * torso) continue;
      final cx = [for (final p in s) p.midHipX!].reduce((a, b) => a + b) / n;
      final offset = (cx - 0.5).abs();
      if (offset < bestOffset) {
        bestOffset = offset;
        bestTrack = track;
        best = Calibration(
          torsoHeight: torso,
          centerX: cx,
          baselineHipY: hips.reduce((a, b) => a + b) / n,
          baselineShoulderY: shoulders.reduce((a, b) => a + b) / n,
        );
      }
    }
    if (best == null) return _fail(CalibrationIssue.notStill);
    if (bestOffset > _maxCenterOffset) {
      return _fail(CalibrationIssue.notCentered);
    }
    final index = bestTrack!.index;
    _reset();
    return CalibrationProgress(
      progress: 1.0,
      result: best,
      selectedPoseIndex: index,
    );
  }
}
