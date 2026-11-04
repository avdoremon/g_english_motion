import 'word_judge.dart';

enum SpeechAvailability {
  available,

  /// The microphone permission was refused.
  noPermission,

  /// The device has no recogniser that works fully on the device. SayIt is
  /// hidden then: a network recogniser is never used instead.
  noOnDeviceRecognizer,
}

/// Speech recognition that runs on the device only: audio never leaves it.
abstract class SpeechSource {
  /// Never asks for anything by default: `available` needs an on-device
  /// recogniser AND a microphone permission that is already granted. With
  /// [askPermission] the permission is requested (only a parent-gated screen
  /// does that).
  Future<SpeechAvailability> check({bool askPermission = false});

  /// One listen: results stamped with [sessionId]; the stream ends when the
  /// recogniser stops (end of speech, silence, or [stop]). Unless [check]
  /// would say `available` it listens to nothing and the stream fails with an
  /// error.
  Stream<RecognitionResult> listenOnce({required int sessionId});

  Future<void> stop();
}
