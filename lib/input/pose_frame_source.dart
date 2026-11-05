import 'dart:async';

import 'pose_types.dart';

export 'confirm_gesture.dart';

enum PermissionOutcome {
  granted,
  denied,
  permanentlyDenied,

  /// The native camera/pose side is absent or cannot run on this device
  /// (e.g. `MissingPluginException`). Not a permission problem.
  unavailable,
}

/// An error the camera/pose side reported while running (e.g. the plugin's
/// `CAMERA_ERROR` / `POSE_ERROR`). One failure does not end a game; the
/// controller gives up only when failures persist without frames.
class PoseSourceFailure {
  const PoseSourceFailure(this.error);

  final Object error;

  @override
  String toString() => 'PoseSourceFailure($error)';
}

/// Source of pose frames (camera + pose model in production, fake in tests).
abstract class PoseFrameSource {
  Future<PermissionOutcome> start();
  Stream<PoseFrame> get frames;

  /// Errors from the camera/pose side (broadcast; never completes by itself).
  /// Frames keep flowing after an error if the source recovers.
  Stream<PoseSourceFailure> get failures;
  Future<void> stop();
}

/// Emits a prepared list (or stream) of frames. The stream is single
/// subscription; frames are delivered once a listener attaches.
class FakePoseFrameSource implements PoseFrameSource {
  FakePoseFrameSource(
    Iterable<PoseFrame> frames, {
    this.outcome = PermissionOutcome.granted,
  }) : _frames = Stream<PoseFrame>.fromIterable(frames);

  FakePoseFrameSource.fromStream(
    Stream<PoseFrame> frames, {
    this.outcome = PermissionOutcome.granted,
  }) : _frames = frames;

  final PermissionOutcome outcome;
  final Stream<PoseFrame> _frames;
  bool started = false;
  bool stopped = false;
  final StreamController<PoseSourceFailure> _failures =
      StreamController<PoseSourceFailure>.broadcast(sync: true);

  /// Test hook: reports a camera/pose error.
  void emitFailure(Object error) => _failures.add(PoseSourceFailure(error));

  @override
  Stream<PoseSourceFailure> get failures => _failures.stream;

  @override
  Future<PermissionOutcome> start() async {
    started = outcome == PermissionOutcome.granted;
    return outcome;
  }

  @override
  Stream<PoseFrame> get frames => _frames;

  @override
  Future<void> stop() async {
    stopped = true;
  }
}
