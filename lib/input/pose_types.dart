/// Pure-Dart pose types. Coordinates are normalized 0..1, y points down.
enum PoseJoint {
  nose,
  leftShoulder,
  rightShoulder,
  leftHip,
  rightHip,
  leftWrist,
  rightWrist,
  leftKnee,
  rightKnee,
}

enum Hand { left, right }

class Landmark {
  const Landmark(this.x, this.y, this.confidence);

  final double x;
  final double y;
  final double confidence;
}

class Pose {
  const Pose(this.joints);

  static const double minConfidence = 0.5;

  final Map<PoseJoint, Landmark> joints;

  Landmark? _reliable(PoseJoint j) {
    final l = joints[j];
    if (l == null || l.confidence < minConfidence) return null;
    return l;
  }

  double? get midHipX {
    final l = _reliable(PoseJoint.leftHip), r = _reliable(PoseJoint.rightHip);
    if (l == null || r == null) return null;
    return (l.x + r.x) / 2;
  }

  double? get midHipY {
    final l = _reliable(PoseJoint.leftHip), r = _reliable(PoseJoint.rightHip);
    if (l == null || r == null) return null;
    return (l.y + r.y) / 2;
  }

  double? get midShoulderY {
    final l = _reliable(PoseJoint.leftShoulder),
        r = _reliable(PoseJoint.rightShoulder);
    if (l == null || r == null) return null;
    return (l.y + r.y) / 2;
  }

  double? get torsoHeight {
    final hip = midHipY, shoulder = midShoulderY;
    if (hip == null || shoulder == null) return null;
    return hip - shoulder;
  }
}

class PoseFrame {
  const PoseFrame(
    this.poses,
    this.timestamp, {
    this.aspectRatio = defaultAspectRatio,
  });

  /// Assumed when the native side does not report the frame size.
  static const double defaultAspectRatio = 16 / 9;

  final List<Pose> poses;
  final Duration timestamp;

  /// Upright frame width / height. x is normalised by the width and y by the
  /// height, so distances on the two axes are only comparable through this.
  final double aspectRatio;
}
