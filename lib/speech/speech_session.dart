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
  });

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
        _run = run;
        unawaited(_loop(run, sessionId, keepListening));
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
    try {
      while (!run.cancelled && keepListening()) {
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
        await run.sub?.cancel();
        run.sub = null;
        if (run.failed) {
          _failed = true;
          break;
        }
        if (!run.cancelled && relistenDelay > Duration.zero) {
          await Future<void>.delayed(relistenDelay);
        }
      }
    } catch (_) {
      // Listening must never break the game.
    } finally {
      _audio.restoreAfterListening();
      if (identical(_run, run)) _run = null;
      if (!run.out.isClosed) unawaited(run.out.close());
    }
  }

  void _finish(StreamController<RecognitionResult> c) {
    final run = _run;
    if (run == null || !identical(run.out, c)) return;
    unawaited(_cancelRun(run));
  }

  Future<void> _cancelRun(_Run run) async {
    run.cancelled = true;
    try {
      await run.sub?.cancel();
    } catch (_) {}
    if (!(run.ended?.isCompleted ?? true)) run.ended!.complete();
    try {
      await _source.stop();
    } catch (_) {}
  }

  /// Stops listening now: the stream ends and the audio is restored.
  Future<void> cancel() async {
    final run = _run;
    if (run == null) return;
    await _cancelRun(run);
    // Let the loop's finally run (restore audio, close the stream).
    await Future<void>.delayed(Duration.zero);
  }
}

class _Run {
  _Run(this.out);
  final StreamController<RecognitionResult> out;
  StreamSubscription<RecognitionResult>? sub;
  Completer<void>? ended;
  bool cancelled = false;
  bool failed = false;
}
