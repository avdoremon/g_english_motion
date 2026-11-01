// Synthetic pose helpers for tests.
//
// API: `Pose makePose({hipX = 0.5, hipY = 0.6, torso = 0.3, confidence = 1.0,
//   noseY, leftWrist, rightWrist, knees = true})`
// - hips at hipY, x = hipX +/- 0.05; shoulders at hipY - torso, x = hipX +/- 0.08
// - nose at x = hipX, y = noseY ?? hipY - torso - 0.1
// - knees at hipY + 0.25 (x = hipX +/- 0.05) when `knees` is true
// - wrists only present when an Offset (x, y) is given
// - every joint gets the given `confidence`
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
      PoseJoint.leftKnee: lm(hipX - 0.05, hipY + 0.25),
      PoseJoint.rightKnee: lm(hipX + 0.05, hipY + 0.25),
    },
  });
}
