import 'pose_types.dart';

export 'confirm_gesture.dart';

enum PermissionOutcome { granted, denied, permanentlyDenied }

/// Source of pose frames (camera + pose model in production, fake in tests).
abstract class PoseFrameSource {
  Future<PermissionOutcome> start();
  Stream<PoseFrame> get frames;
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
