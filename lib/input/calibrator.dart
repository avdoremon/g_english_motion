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

/// Averages ~[hold] of frames, picks the still pose closest to the center.
class Calibrator {
  Calibrator({this.hold = const Duration(seconds: 2)});

  final Duration hold;

  /// Frame-interval slack so that N frames at 30 fps spanning (N-1) intervals
  /// count as a full hold of N/30 s.
  static const Duration _frameSlack = Duration(milliseconds: 40);
  static const double _stillRatio = 0.02;
  static const double _maxCenterOffset = 0.2;
  static const double _minNoseY = 0.08;
  static const double _minCoverage = 0.8;

  Duration? _start;
  int _frames = 0;
  final Map<int, List<Pose>> _samples = {};

  void _reset() {
    _start = null;
    _frames = 0;
    _samples.clear();
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
    if (!anyPerson) return _fail(CalibrationIssue.noPerson);
    if (usable.isEmpty) return _fail(CalibrationIssue.tooClose);

    _start ??= f.timestamp;
    _frames++;
    usable.forEach((i, p) => (_samples[i] ??= []).add(p));

    final elapsed = f.timestamp - _start! + _frameSlack;
    final progress = (elapsed.inMicroseconds / hold.inMicroseconds).clamp(
      0.0,
      1.0,
    );
    if (progress < 1.0) return CalibrationProgress(progress: progress);
    return _finish();
  }

  CalibrationProgress _finish() {
    int? bestIndex;
    double bestOffset = double.infinity;
    Calibration? best;
    for (final entry in _samples.entries) {
      final s = entry.value;
      if (s.length < _minCoverage * _frames) continue;
      final n = s.length;
      final hips = [for (final p in s) p.midHipY!];
      final shoulders = [for (final p in s) p.midShoulderY!];
      final torso =
          [for (final p in s) p.torsoHeight!].reduce((a, b) => a + b) / n;
      final minHip = hips.reduce((a, b) => a < b ? a : b);
      final maxHip = hips.reduce((a, b) => a > b ? a : b);
      if (maxHip - minHip >= _stillRatio * torso) continue;
      final cx = [for (final p in s) p.midHipX!].reduce((a, b) => a + b) / n;
      final offset = (cx - 0.5).abs();
      if (offset < bestOffset) {
        bestOffset = offset;
        bestIndex = entry.key;
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
    _reset();
    return CalibrationProgress(
      progress: 1.0,
      result: best,
      selectedPoseIndex: bestIndex,
    );
  }
}
