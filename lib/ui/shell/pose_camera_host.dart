import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Hosts the `flutter_mp_pose_landmarker` camera preview platform view,
/// invisibly, so the plugin's CameraX session can run.
///
/// Why it exists: the plugin binds a CameraX `Preview` use case to its
/// `PreviewView` together with the `ImageAnalysis` that feeds MediaPipe. That
/// preview surface only exists once the view is attached through this
/// platform view (`camera_preview_view`, registered by the plugin; the
/// package ships no Dart widget for it, `NativeCameraPreview` is only in its
/// example app). Without it the capture session is expected not to start, so
/// no pose results arrive (not verifiable without a device; see
/// docs/pose-plugin-evaluation.md).
///
/// Rules:
/// - Exactly ONE host at a time: the plugin hands the same Android view to
///   every platform view it creates, so two live hosts would put one view in
///   two parents (Android crash). GameShell owns the only one.
/// - Never zero-size (creation is deferred until it has a size) and never
///   opacity 0 (Flutter then skips painting the view): 1 x 1 logical pixel at
///   1% opacity, ignoring touches and hidden from semantics.
/// - Renders nothing off Android (no native side there).
class PoseCameraHost extends StatelessWidget {
  const PoseCameraHost({super.key});

  /// Platform view type registered by the plugin's Android side.
  static const String viewType = 'camera_preview_view';

  @override
  Widget build(BuildContext context) {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const SizedBox.shrink();
    }
    return const IgnorePointer(
      child: ExcludeSemantics(
        child: Opacity(
          opacity: 0.01,
          child: SizedBox(
            width: 1,
            height: 1,
            child: AndroidView(
              viewType: viewType,
              layoutDirection: TextDirection.ltr,
            ),
          ),
        ),
      ),
    );
  }
}
