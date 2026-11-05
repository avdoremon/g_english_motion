import 'package:flutter_mp_pose_landmarker/flutter_mp_pose_landmarker.dart';

import 'plugin_pose_frame_source.dart';

/// Production [PoseLandmarkerBackend]: the published `flutter_mp_pose_landmarker`
/// plugin, untouched. Deliberately minimal (no logic worth unit testing);
/// docs/pose-plugin-evaluation.md lists what the native side does.
class MpPoseLandmarkerBackend implements PoseLandmarkerBackend {
  const MpPoseLandmarkerBackend();

  /// Requested CameraX analysis size (4:3). The app is landscape-only and
  /// the plugin rotates frames upright, so the analysed image is 640 x 480.
  static const int analysisWidth = 640;
  static const int analysisHeight = 480;

  /// The plugin does not report the image size; assume the requested one.
  @override
  double get assumedAspectRatio => analysisWidth / analysisHeight;

  /// CPU delegate + lite model: the plugin's GPU path only falls back to the
  /// CPU on a Java exception, not on a native GPU crash, and the lite model
  /// is plenty for coarse lane/jump detection.
  @override
  Future<void> configure() => PoseLandmarker.setConfig(
    delegate: 0,
    model: 1,
    analysisWidth: analysisWidth,
    analysisHeight: analysisHeight,
  );

  /// Listening starts CameraX (plugin `onListen`), cancelling the last
  /// listener unbinds it (`onCancel` → `releaseCamera`).
  @override
  Stream<RawPoseResult> results() => PoseLandmarker.poseLandmarkStream.map(
    (p) => RawPoseResult(
      timestampMs: p.timestampMs,
      landmarks: [
        for (final l in p.landmarks)
          RawPoseLandmark(
            x: l.x,
            y: l.y,
            visibility: l.visibility,
            presence: l.presence,
          ),
      ],
    ),
  );
}
