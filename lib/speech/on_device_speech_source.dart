import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'speech_source.dart';
import 'word_judge.dart';

/// Thin seam over the `speech_to_text` plugin (and the one platform question
/// the plugin cannot answer), so [OnDeviceSpeechSource] is unit-testable
/// without the plugin.
abstract class SpeechBackend {
  /// Whether this device has a recogniser that runs fully on the device.
  Future<bool> isOnDeviceAvailable();

  /// Microphone permission already granted (never asks).
  Future<bool> hasPermission();

  /// Asks for the microphone permission; true when granted.
  Future<bool> requestPermission();

  /// Prepares the recogniser (only called once the permission is granted).
  /// False when it cannot be used.
  Future<bool> initialize();

  /// Starts one on-device listen in en_US. [onEnd] fires once, when the
  /// recogniser has finished (after any final result; error code null) or
  /// failed (the plugin's error code, e.g. `error_busy`).
  ///
  /// Returns false when the recogniser did NOT start. The plugin's Android
  /// side answers false - with no status and no error callback - when it
  /// still believes it is listening or was never initialised, and
  /// `SpeechToText.listen` swallows that answer, so a caller that ignores it
  /// waits forever for an [onEnd] that never comes.
  Future<bool> listen({
    required String localeId,
    required void Function(List<String> transcripts, List<double> confidences)
    onResult,
    required void Function(String? errorCode) onEnd,
  });

  /// How long after a started [listen] the caller may wait for [onEnd]
  /// before treating the listen as dead.
  Duration get listenTimeout;

  Future<void> stop();
}

/// Plugin error codes that only mean "nothing was said": the listen ends
/// normally and the session listens again. Every other code is a failure.
bool isBenignSpeechError(String code) =>
    code == 'error_no_match' || code == 'error_speech_timeout';

/// Reported when a listen never started, or started and never ended. Not
/// benign: the caller must count it as a failure, never as silence.
const String speechNotStartedError = 'error_not_started';

/// Recognition that never leaves the device. Audio and transcripts exist only
/// in memory, inside the stream events.
///
/// Privacy rule: this class never listens unless [check] is `available`,
/// which requires an on-device recogniser. There is no fallback to a
/// recogniser that may use the network.
class OnDeviceSpeechSource implements SpeechSource {
  OnDeviceSpeechSource(this._backend);

  final SpeechBackend _backend;
  static const localeId = 'en_US';

  Future<SpeechAvailability>? _checked;
  StreamController<RecognitionResult>? _active;
  Future<bool>? _initialized;

  /// Fires when a started listen has not ended in time (see
  /// [SpeechBackend.listenTimeout]).
  Timer? _watchdog;

  @override
  Future<SpeechAvailability> check({bool askPermission = false}) {
    // Only a positive answer is cached: a refused permission may be granted
    // later (system settings, or the parent turning SayIt on).
    final cached = _checked;
    if (cached != null) return cached;
    final f = _check(askPermission);
    _checked = f.then((a) {
      if (a != SpeechAvailability.available) _checked = null;
      return a;
    });
    return _checked!;
  }

  Future<SpeechAvailability> _check(bool ask) async {
    try {
      // First: a device that cannot recognise on-device is out, and the
      // microphone permission is not asked for nothing.
      if (!await _backend.isOnDeviceAvailable()) {
        return SpeechAvailability.noOnDeviceRecognizer;
      }
      var granted = await _backend.hasPermission();
      if (!granted && ask) granted = await _backend.requestPermission();
      return granted
          ? SpeechAvailability.available
          : SpeechAvailability.noPermission;
    } catch (e) {
      debugPrint('OnDeviceSpeechSource.check failed: $e');
      return SpeechAvailability.noOnDeviceRecognizer;
    }
  }

  @override
  Stream<RecognitionResult> listenOnce({required int sessionId}) {
    late StreamController<RecognitionResult> c;
    c = StreamController<RecognitionResult>(
      onListen: () => unawaited(_start(c, sessionId)),
      onCancel: () async {
        if (identical(_active, c)) {
          _active = null;
          _cancelWatchdog();
          await _safeStop();
        }
      },
    );
    return c.stream;
  }

  void _cancelWatchdog() {
    _watchdog?.cancel();
    _watchdog = null;
  }

  Future<void> _start(StreamController<RecognitionResult> c, int id) async {
    void end([String? errorCode]) {
      _cancelWatchdog();
      if (identical(_active, c)) _active = null;
      if (c.isClosed) return;
      // "Heard nothing" is a normal end; any other code is a failure the
      // caller must not mistake for silence.
      if (errorCode != null && !isBenignSpeechError(errorCode)) {
        c.addError(StateError('speech recognition failed: $errorCode'));
      }
      unawaited(c.close());
    }

    try {
      if (await check() != SpeechAvailability.available) {
        // Loud, not silent: the caller must not mistake "could not listen"
        // for "heard nothing".
        throw StateError('on-device speech recognition is not available');
      }
      // One listen at a time. The recogniser is stopped unconditionally: on
      // the normal relisten path the previous controller is already closed,
      // yet the plugin may still hold the microphone - and a plugin that
      // thinks it is listening refuses to start without saying so.
      final previous = _active;
      _active = c;
      _cancelWatchdog();
      await _safeStop();
      if (previous != null && !previous.isClosed) unawaited(previous.close());
      if (c.isClosed) return;
      _initialized ??= _backend.initialize();
      if (!await _initialized!) {
        _initialized = null;
        throw StateError('speech recognizer could not be initialised');
      }
      if (c.isClosed) return;
      final started = await _backend.listen(
        localeId: localeId,
        onResult: (transcripts, confidences) {
          // A result of a finished (or superseded) listen is dropped.
          if (c.isClosed || !identical(_active, c)) return;
          c.add(
            RecognitionResult(
              transcripts: List.unmodifiable(transcripts),
              confidences: List.unmodifiable(confidences),
              sessionId: id,
            ),
          );
        },
        onEnd: end,
      );
      // The listen may already have ended (synchronously, or while awaiting).
      if (c.isClosed || !identical(_active, c)) return;
      if (!started) {
        debugPrint('OnDeviceSpeechSource: the recogniser did not start');
        end(speechNotStartedError);
        return;
      }
      // Nothing ending in time means the microphone never opened: a listen
      // that is never reported would be graded as silence.
      _watchdog = Timer(_backend.listenTimeout, () {
        if (!identical(_active, c)) return;
        debugPrint('OnDeviceSpeechSource: the recogniser never ended');
        end(speechNotStartedError);
      });
    } catch (e) {
      debugPrint('OnDeviceSpeechSource.listenOnce failed: $e');
      _initialized = null;
      if (!c.isClosed) c.addError(e);
      end();
    }
  }

  Future<void> _safeStop() async {
    try {
      await _backend.stop();
    } catch (_) {}
  }

  @override
  Future<void> stop() async {
    final c = _active;
    _active = null;
    _cancelWatchdog();
    await _safeStop();
    if (c != null && !c.isClosed) await c.close();
  }
}

/// The real backend: the `speech_to_text` plugin plus one tiny platform call.
///
/// Why the extra platform call: on Android the plugin silently falls back to
/// the default recogniser (which may use the network) when the on-device one
/// is missing or the OS is older than API 31, even when `onDevice: true` is
/// requested. So the app asks the OS first
/// (`SpeechRecognizer.isOnDeviceRecognitionAvailable`) and [listen] refuses to
/// run unless that answered yes. [listenOptions] always sets `onDevice: true`;
/// that is checked by a unit test.
///
/// Not unit-tested itself (needs a device): see the speech section of the
/// on-device checklist in the task report.
class SpeechToTextBackend implements SpeechBackend {
  SpeechToTextBackend({SpeechToText? plugin, MethodChannel? channel})
    : _stt = plugin ?? SpeechToText(),
      _channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'vn.avdoremon.g_english_motion/speech';

  /// The only options a listen is ever started with.
  static final SpeechListenOptions listenOptions = SpeechListenOptions(
    onDevice: true,
    localeId: OnDeviceSpeechSource.localeId,
    // Only final results: a half-heard word is never judged.
    partialResults: false,
    cancelOnError: true,
    listenMode: ListenMode.confirmation,
    pauseFor: const Duration(seconds: 3),
    listenFor: const Duration(seconds: 20),
  );

  final SpeechToText _stt;
  final MethodChannel _channel;
  bool _onDeviceVerified = false;
  void Function(String? errorCode)? _onEnd;

  @override
  Future<bool> isOnDeviceAvailable() async {
    final ok =
        await _channel.invokeMethod<bool>('isOnDeviceRecognitionAvailable') ??
        false;
    _onDeviceVerified = ok;
    return ok;
  }

  @override
  Future<bool> hasPermission() => Permission.microphone.isGranted;

  @override
  Future<bool> requestPermission() async =>
      (await Permission.microphone.request()).isGranted;

  @override
  Future<bool> initialize() => _stt.initialize(
    onStatus: _onStatus,
    onError: _onError,
    options: [SpeechToText.androidNoBluetooth],
  );

  void _onStatus(String status) {
    // 'done' comes after the final result; 'notListening' can come before it.
    if (status == SpeechToText.doneStatus) _fireEnd(null);
  }

  void _onError(SpeechRecognitionError e) => _fireEnd(e.errorMsg);

  void _fireEnd(String? code) {
    final f = _onEnd;
    _onEnd = null;
    f?.call(code);
  }

  /// The plugin's own `listenFor` plus a margin: past that a listen that has
  /// not reported an end is not running.
  @override
  Duration get listenTimeout =>
      (listenOptions.listenFor ?? const Duration(seconds: 20)) +
      const Duration(seconds: 2);

  @override
  Future<bool> listen({
    required String localeId,
    required void Function(List<String>, List<double>) onResult,
    required void Function(String? errorCode) onEnd,
  }) async {
    if (!_onDeviceVerified) {
      throw StateError('on-device recognition was not verified');
    }
    _onEnd = onEnd;
    await _stt.listen(
      listenOptions: listenOptions,
      onResult: (SpeechRecognitionResult r) {
        // Not persisted or logged.
        onResult(
          [for (final a in r.alternates) a.recognizedWords],
          [for (final a in r.alternates) a.confidence],
        );
      },
    );
    // `SpeechToText.listen` discards the platform's false answer, so the
    // only way to tell a refused start from a started listen is to ask.
    return _stt.isListening;
  }

  @override
  Future<void> stop() {
    // A late 'done' from this cancelled listen must not end the next one.
    _onEnd = null;
    return _stt.cancel();
  }
}
