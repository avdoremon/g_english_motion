// Synthetic pose helpers for tests.
//
// API: `Pose makePose({hipX = 0.5, hipY = 0.6, torso = 0.3, confidence = 1.0,
//   noseY, leftWrist, rightWrist, knees = true, kneeY})`
// - hips at hipY, x = hipX +/- 0.05; shoulders at hipY - torso, x = hipX +/- 0.08
// - nose at x = hipX, y = noseY ?? hipY - torso - 0.1
// - knees at kneeY ?? hipY + 0.25 (x = hipX +/- 0.05) when `knees` is true
// - wrists only present when an Offset (x, y) is given
// - every joint gets the given `confidence`
import 'dart:math' as math;
import 'dart:ui' show Offset;

import 'package:g_english_motion/input/pose_types.dart';

Pose makePose({
  double hipX = 0.5,
  double hipY = 0.6,
  double torso = 0.3,
  double confidence = 1.0,
  double? noseY,
  Offset? leftWrist,
  Offset? rightWrist,
  bool knees = true,
  double? kneeY,
}) {
  Landmark lm(double x, double y) => Landmark(x, y, confidence);
  final shoulderY = hipY - torso;
  return Pose({
    PoseJoint.nose: lm(hipX, noseY ?? shoulderY - 0.1),
    PoseJoint.leftShoulder: lm(hipX - 0.08, shoulderY),
    PoseJoint.rightShoulder: lm(hipX + 0.08, shoulderY),
    PoseJoint.leftHip: lm(hipX - 0.05, hipY),
    PoseJoint.rightHip: lm(hipX + 0.05, hipY),
    if (leftWrist != null) PoseJoint.leftWrist: lm(leftWrist.dx, leftWrist.dy),
    if (rightWrist != null)
      PoseJoint.rightWrist: lm(rightWrist.dx, rightWrist.dy),
    if (knees) ...{
      PoseJoint.leftKnee: lm(hipX - 0.05, kneeY ?? hipY + 0.25),
      PoseJoint.rightKnee: lm(hipX + 0.05, kneeY ?? hipY + 0.25),
    },
  });
}

// ---------------------------------------------------------------------------
// Sequence helpers (30 fps by default). Added in Task 3.
// ---------------------------------------------------------------------------

/// Builds frames at [fps] for [duration]; frame i is at start + i/fps and
/// holds the poses returned by [posesAt] (called with the frame timestamp).
List<PoseFrame> poseSequence({
  required Duration duration,
  required List<Pose> Function(Duration t) posesAt,
  int fps = 30,
  Duration start = Duration.zero,
}) {
  final count = (duration.inMicroseconds * fps / 1e6).round();
  return [
    for (var i = 0; i < count; i++)
      () {
        final t = start + Duration(microseconds: (i * 1e6 / fps).round());
        return PoseFrame(posesAt(t), t);
      }(),
  ];
}

/// Deterministic pseudo-noise in [-amp, amp] (no dart:math Random needed).
double _noise(int i, double amp) =>
    amp * math.sin(i * 12.9898 + 4.1414) * math.cos(i * 78.233);

/// One person standing still, optionally with tiny deterministic jitter.
List<PoseFrame> standingSequence({
  required Duration duration,
  int fps = 30,
  Duration start = Duration.zero,
  double hipX = 0.5,
  double hipY = 0.6,
  double torso = 0.3,
  double noise = 0.0,
}) {
  var i = 0;
  return poseSequence(
    duration: duration,
    fps: fps,
    start: start,
    posesAt: (_) => [
      makePose(hipX: hipX, hipY: hipY + _noise(i++, noise), torso: torso),
    ],
  );
}

/// [jumps] jumps: each is a half-sine lift of peak [rise] (normalized units,
/// whole body moves up) lasting [airtime], separated by [rest] of standing;
/// starts with [leadIn] of standing.
List<PoseFrame> jumpSequence({
  required int jumps,
  double rise = 0.06,
  Duration airtime = const Duration(milliseconds: 500),
  Duration rest = const Duration(milliseconds: 1500),
  Duration leadIn = const Duration(milliseconds: 1500),
  int fps = 30,
  double hipY = 0.6,
  double torso = 0.3,
  double noise = 0.002,
}) {
  final period = airtime + rest;
  final total = leadIn + period * jumps;
  var i = 0;
  return poseSequence(
    duration: total,
    fps: fps,
    posesAt: (t) {
      var lift = 0.0;
      final since = t - leadIn;
      if (!since.isNegative) {
        final inPeriod = since.inMicroseconds % period.inMicroseconds;
        if (inPeriod < airtime.inMicroseconds) {
          lift = rise * math.sin(math.pi * inPeriod / airtime.inMicroseconds);
        }
      }
      return [makePose(hipY: hipY - lift + _noise(i++, noise), torso: torso)];
    },
  );
}

/// Player slowly backing away: torso shrinks [fromTorso] -> [toTorso] and the
/// hips drift up [hipYFrom] -> [hipYTo] while shoulders stay put. No jump.
List<PoseFrame> backingAwaySequence({
  Duration duration = const Duration(seconds: 5),
  int fps = 30,
  double fromTorso = 0.3,
  double toTorso = 0.25,
  double hipYFrom = 0.6,
  double hipYTo = 0.55,
}) {
  return poseSequence(
    duration: duration,
    fps: fps,
    posesAt: (t) {
      final u = t.inMicroseconds / duration.inMicroseconds;
      final torso = fromTorso + (toTorso - fromTorso) * u;
      final hipY = hipYFrom + (hipYTo - hipYFrom) * u;
      return [makePose(hipY: hipY, torso: torso)];
    },
  );
}

// ---------------------------------------------------------------------------
// Multi-person helpers. Added in Task 5.
// ---------------------------------------------------------------------------

/// Returns [frames] with [extra] appended to every frame's pose list
/// (or prepended when [first] is true). Timestamps are unchanged.
List<PoseFrame> withExtraPerson(
  List<PoseFrame> frames,
  Pose extra, {
  bool first = false,
}) {
  return [
    for (final f in frames)
      PoseFrame(first ? [extra, ...f.poses] : [...f.poses, extra], f.timestamp),
  ];
}

/// Returns [frames] with the pose at [index] replaced by [replace].
List<PoseFrame> replacePoseAt(
  List<PoseFrame> frames,
  int index,
  List<Pose> Function(PoseFrame f) replace,
) {
  return [
    for (var i = 0; i < frames.length; i++)
      i == index
          ? PoseFrame(replace(frames[i]), frames[i].timestamp)
          : frames[i],
  ];
}
