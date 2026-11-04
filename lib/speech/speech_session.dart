import 'dart:async';

import '../audio/audio_service.dart';
import 'speech_source.dart';
import 'word_judge.dart';

/// Keeps the microphone open for as long as a word runs: music and effects are
/// muted while listening (so the mic does not hear the TV) and restored when
/// done, however it ends; the recogniser is restarted when it stops on its
/// own (silence). A source failure ends the session quietly.
class SpeechSession {
  SpeechSession(
    this._source,
    this._audio, {
    this.relistenDelay = const Duration(milliseconds: 100),
    this.maxConsecutiveFailures = 3,
  });

  /// After this many failed listens in a row the session gives up and
  /// [failed] becomes true (a listen that ends normally resets the count).
  final int maxConsecutiveFailures;

  final SpeechSource _source;
  final AudioService _audio;

  /// Pause before listening again, so a recogniser that ends at once cannot
  /// spin the CPU.
  final Duration relistenDelay;

  _Run? _run;
  bool _failed = false;

  /// Whether the last listening ended because the source failed (as opposed
  /// to being stopped). Then "heard nothing" must not be held against the
  /// child.
  bool get failed => _failed;

  Stream<RecognitionResult> listenWhile({
    required int sessionId,
    required bool Function() keepListening,
  }) {
    late StreamController<RecognitionResult> c;
    c = StreamController<RecognitionResult>(
      onListen: () {
        final run = _Run(c);
        final previous = _run;
        _run = run;
        unawaited(() async {
          // The earlier listen is fully stopped (and the audio restored)
          // before this one mutes and opens the microphone again.
          if (previous != null) {
            await _cancelRun(previous);
            await previous.finished.future;
          }
          await _loop(run, sessionId, keepListening);
        }());
      },
      onCancel: () => _finish(c),
    );
    return c.stream;
  }

  Future<void> _loop(
    _Run run,
    int sessionId,
    bool Function() keepListening,
  ) async {
    _failed = false;
    _audio.muteForListening();
    var failures = 0;
    try {
      while (!run.cancelled && keepListening()) {
        run.failed = false;
        final ended = Completer<void>();
        run.ended = ended;
        run.sub = _source
            .listenOnce(sessionId: sessionId)
            .listen(
              (r) {
                if (!run.cancelled && !run.out.isClosed) run.out.add(r);
              },
              onError: (Object _) {
                run.failed = true;
                if (!ended.isCompleted) ended.complete();
              },
              onDone: () {
                if (!ended.isCompleted) ended.complete();
              },
              cancelOnError: true,
            );
        await ended.future;
        // Not awaited: the audio must be restored whatever the source does.
        unawaited(run.sub?.cancel());
        run.sub = null;
        if (run.failed) {
          failures++;
          if (failures >= maxConsecutiveFailures) {
            _failed = true;
            break;
          }
        } else {
          failures = 0;
        }
        if (!run.cancelled && relistenDelay > Duration.zero) {
          final wake = run.wake = Completer<void>();
          final timer = Timer(relistenDelay, () {
            if (!wake.isCompleted) wake.complete();
          });
          await wake.future;
          timer.cancel();
        }
      }
    } catch (_) {
      // Listening must never break the game.
    } finally {
      _audio.restoreAfterListening();
      if (identical(_run, run)) _run = null;
      if (!run.out.isClosed) unawaited(run.out.close());
      if (!run.finished.isCompleted) run.finished.complete();
    }
  }

  void _finish(StreamController<RecognitionResult> c) {
    final run = _run;
    if (run == null || !identical(run.out, c)) return;
    unawaited(_cancelRun(run));
  }

  Future<void> _cancelRun(_Run run) async {
    run.cancelled = true;
    unawaited(run.sub?.cancel());
    if (!(run.ended?.isCompleted ?? true)) run.ended!.complete();
    if (!(run.wake?.isCompleted ?? true)) run.wake!.complete();
    try {
      await _source.stop();
    } catch (_) {}
  }

  /// Stops listening now: the stream ends and the audio is restored.
  Future<void> cancel() async {
    final run = _run;
    if (run == null) return;
    await _cancelRun(run);
    // The loop's tail restores the audio and closes the stream.
    await run.finished.future;
  }
}

class _Run {
  _Run(this.out);
  final StreamController<RecognitionResult> out;
  StreamSubscription<RecognitionResult>? sub;
  Completer<void>? ended, wake;
  final Completer<void> finished = Completer<void>();
  bool cancelled = false;
  bool failed = false;
}
