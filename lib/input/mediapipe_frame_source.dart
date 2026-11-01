import 'package:flutter/services.dart';

import 'pose_frame_source.dart';
import 'pose_types.dart';

/// Pose frames from the native MediaPipe pipeline over platform channels.
/// See docs/native-pose-channel.md for the contract the native side must meet.
///
/// Privacy: frames are mapped and forwarded only; nothing is stored or saved.
class MediapipeFrameSource implements PoseFrameSource {
  MediapipeFrameSource({
    this.numPoses = 2,
    this.frontCamera = true,
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
  })  : _method = methodChannel ?? const MethodChannel(methodChannelName),
        _events = eventChannel ?? const EventChannel(eventChannelName);

  static const methodChannelName = 'vn.avdoremon.g_english_motion/pose';
  static const eventChannelName = 'vn.avdoremon.g_english_motion/pose_frames';

  final int numPoses;
  final bool frontCamera;
  final MethodChannel _method;
  final EventChannel _events;

  @override
  Future<PermissionOutcome> start() async {
    try {
      final result = await _method.invokeMethod<String>('start', {
        'numPoses': numPoses,
        'frontCamera': frontCamera,
      });
      return switch (result) {
        'granted' => PermissionOutcome.granted,
        'permanentlyDenied' => PermissionOutcome.permanentlyDenied,
        _ => PermissionOutcome.denied,
      };
    } on PlatformException catch (e) {
      return e.code == 'PERMISSION_PERMANENTLY_DENIED'
          ? PermissionOutcome.permanentlyDenied
          : PermissionOutcome.denied;
    } on MissingPluginException {
      return PermissionOutcome.unavailable;
    } catch (_) {
      return PermissionOutcome.denied;
    }
  }

  /// Broadcast stream; malformed events and platform errors are dropped.
  @override
  Stream<PoseFrame> get frames => _events
      .receiveBroadcastStream()
      .handleError((Object _) {})
      .expand<PoseFrame>((event) {
    final frame = _parse(event);
    return frame == null ? const [] : [frame];
  });

  @override
  Future<void> stop() async {
    try {
      await _method.invokeMethod<void>('stop');
    } catch (_) {
      // Stopping must never throw.
    }
  }

  static final Map<String, PoseJoint> _joints = {
    for (final j in PoseJoint.values) j.name: j,
  };

  static PoseFrame? _parse(Object? event) {
    try {
      if (event is! Map) return null;
      final ts = event['timestampMicros'];
      final rawPoses = event['poses'];
      if (ts is! int || rawPoses is! List) return null;
      final poses = <Pose>[];
      for (final p in rawPoses) {
        if (p is! Map) return null;
        final lms = p['landmarks'];
        if (lms is! Map) return null;
        final joints = <PoseJoint, Landmark>{};
        for (final entry in lms.entries) {
          final joint = _joints[entry.key];
          if (joint == null) continue;
          final v = entry.value;
          if (v is! Map) return null;
          final x = v['x'], y = v['y'], c = v['confidence'];
          if (x is! num || y is! num || c is! num) return null;
          joints[joint] = Landmark(x.toDouble(), y.toDouble(), c.toDouble());
        }
        poses.add(Pose(joints));
      }
      return PoseFrame(poses, Duration(microseconds: ts));
    } catch (_) {
      return null;
    }
  }
}
