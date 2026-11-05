import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/audio/audio_service.dart';
import 'package:g_english_motion/speech/speech_session.dart';
import 'package:g_english_motion/speech/speech_source.dart';
import 'package:g_english_motion/speech/word_judge.dart';

class LogTts implements SpeechEngine {
  @override
  Future<bool> isEnglishAvailable() async => true;
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class LogClips implements ClipPlayer {
  @override
  Future<bool> play(String assetPath) async => true;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

/// Records mute state into the shared log.
class LoggedAudio extends AudioService {
  LoggedAudio(this.log)
    : super(LogTts(), LogClips(), assetExists: (_) => false);
  final List<String> log;
  @override
  void muteForListening() {
    log.add('mute');
    super.muteForListening();
  }

  @override
  void restoreAfterListening() {
    log.add('restore');
    super.restoreAfterListening();
  }
}

/// Muting blows up (e.g. the audio engine is gone): the session must still
/// restore and must not leave `cancel()` waiting forever.
class _ThrowingMuteAudio extends LoggedAudio {
  _ThrowingMuteAudio(super.log);
  @override
  void muteForListening() {
    log.add('mute');
    throw StateError('audio gone');
  }
}

class FakeSource implements SpeechSource {
  FakeSource(this.log);
  final List<String> log;
  final List<StreamController<RecognitionResult>> streams = [];
  final List<int> ids = [];
  Object? failWith;

  /// Per-call override: returns the error to fail with, or null to succeed.
  Object? Function(int sessionId)? onListen;
  int stops = 0;

  @override
  Future<SpeechAvailability> check({bool askPermission = false}) async =>
      SpeechAvailability.available;

  @override
  Stream<RecognitionResult> listenOnce({required int sessionId}) {
    log.add('listen');
    ids.add(sessionId);
    final err = onListen != null ? onListen!(sessionId) : failWith;
    if (err != null) return Stream.error(err);
    final c = StreamController<RecognitionResult>();
    streams.add(c);
    return c.stream;
  }

  @override
  Future<void> stop() async {
    stops++;
    log.add('stop');
  }
}

RecognitionResult res(String s, int id) =>
    RecognitionResult(transcripts: [s], sessionId: id);

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late List<String> log;
  late FakeSource src;
  late LoggedAudio audio;
  late SpeechSession session;

  setUp(() {
    log = [];
    src = FakeSource(log);
    audio = LoggedAudio(log);
    session = SpeechSession(src, audio, relistenDelay: Duration.zero);
  });

  test('mutes before the first listen and relistens while wanted', () async {
    var keep = true;
    final got = <RecognitionResult>[];
    final done = Completer<void>();
    session
        .listenWhile(sessionId: 7, keepListening: () => keep)
        .listen(got.add, onDone: done.complete);
    await settle();
    expect(session.failed, isFalse);
    expect(log, ['mute', 'listen']);
    expect(audio.muted, isTrue);
    src.streams[0].add(res('cat', 7));
    await settle();
    expect(got.single.sessionId, 7);
    // Recognizer stopped (silence) while the word still runs: listen again.
    await src.streams[0].close();
    await settle();
    expect(src.streams, hasLength(2));
    expect(src.ids, [7, 7]);
    keep = false;
    await src.streams[1].close();
    await done.future;
    expect(src.streams, hasLength(2), reason: 'no third listen');
    expect(log.last, 'restore');
    expect(audio.muted, isFalse);
  });

  test('keepListening false after the first stream: stops, restores', () async {
    final done = Completer<void>();
    session
        .listenWhile(sessionId: 1, keepListening: () => false)
        .listen((_) {}, onDone: done.complete);
    await settle();
    // Not wanted at all: never even listens, but never leaves audio muted.
    await done.future;
    expect(src.streams, isEmpty);
    expect(audio.muted, isFalse);
  });

  test('a failing source is retried up to 4 times, then failed', () async {
    src.failWith = StateError('boom');
    final errors = <Object>[];
    final done = Completer<void>();
    session
        .listenWhile(sessionId: 1, keepListening: () => true)
        .listen((_) {}, onError: errors.add, onDone: done.complete);
    await done.future;
    expect(errors, isEmpty, reason: 'never throws');
    expect(src.ids, [1, 1, 1, 1], reason: 'failure cap of 4');
    expect(session.failed, isTrue);
    expect(log.first, 'mute');
    expect(log.last, 'restore');
    expect(audio.muted, isFalse);
  });

  test('a normal end resets the failure count', () async {
    var n = 0;
    // calls 1,2 fail; 3 listens; 4,5 fail; 6 listens: never 4 in a row.
    src.onListen = (id) {
      n++;
      return (n == 3 || n >= 6) ? null : StateError('x');
    };
    session.listenWhile(sessionId: 1, keepListening: () => true).listen((_) {});
    await settle();
    await settle();
    expect(n, 3);
    await src.streams[0].close();
    await settle();
    await settle();
    expect(n, 6);
    expect(session.failed, isFalse);
    await session.cancel();
  });

  group('retry backoff', () {
    test('grows with consecutive failures and resets on a success', () {
      final s = SpeechSession(
        src,
        audio,
        relistenDelay: const Duration(milliseconds: 100),
      );
      expect(s.relistenDelayAfter(0), const Duration(milliseconds: 100));
      expect(s.relistenDelayAfter(1), const Duration(milliseconds: 100));
      expect(s.relistenDelayAfter(2), const Duration(milliseconds: 400));
      expect(s.relistenDelayAfter(3), const Duration(seconds: 1));
      expect(s.relistenDelayAfter(9), const Duration(seconds: 1));
    });

    test('the recogniser is stopped before each retry', () async {
      src.failWith = StateError('boom');
      final done = Completer<void>();
      session
          .listenWhile(sessionId: 1, keepListening: () => true)
          .listen((_) {}, onDone: done.complete);
      await done.future;
      expect(log, [
        'mute',
        'listen',
        'stop',
        'listen',
        'stop',
        'listen',
        'stop',
        'listen',
        'restore',
      ]);
    });

    test('the mic failure budget is over a second, not ~200 ms', () async {
      // The mic-problem overlay halts the level and the phone is across the
      // room: the cap must not be spent on a 200 ms hiccup.
      final slow = SpeechSession(src, audio);
      src.failWith = StateError('boom');
      final sw = Stopwatch()..start();
      final done = Completer<void>();
      slow
          .listenWhile(sessionId: 1, keepListening: () => true)
          .listen((_) {}, onDone: done.complete);
      await done.future;
      sw.stop();
      expect(slow.failed, isTrue);
      expect(sw.elapsedMilliseconds, greaterThan(1000));
    });
  });

  test('a throwing muteForListening still restores and never hangs', () async {
    final s = SpeechSession(
      src,
      _ThrowingMuteAudio(log),
      relistenDelay: Duration.zero,
    );
    final done = Completer<void>();
    s
        .listenWhile(sessionId: 1, keepListening: () => true)
        .listen((_) {}, onDone: done.complete);
    await settle();
    await s.cancel().timeout(const Duration(seconds: 5));
    await done.future.timeout(const Duration(seconds: 5));
    expect(log, contains('restore'));
  });

  test('a new listen waits for the previous one to be cancelled', () async {
    final done1 = Completer<void>();
    session
        .listenWhile(sessionId: 1, keepListening: () => true)
        .listen((_) {}, onDone: done1.complete);
    await settle();
    expect(audio.muted, isTrue);
    session.listenWhile(sessionId: 2, keepListening: () => true).listen((_) {});
    await settle();
    await settle();
    await done1.future;
    expect(src.ids, [1, 2]);
    // restore of run 1 happened before run 2 muted again
    expect(log.where((e) => e == 'restore').length, greaterThanOrEqualTo(1));
    expect(log.indexOf('restore'), lessThan(log.lastIndexOf('mute')));
    expect(audio.muted, isTrue);
  });

  test('cancel() stops the source, ends the stream and restores', () async {
    final done = Completer<void>();
    final got = <RecognitionResult>[];
    session
        .listenWhile(sessionId: 3, keepListening: () => true)
        .listen(got.add, onDone: done.complete);
    await settle();
    await session.cancel();
    await done.future;
    expect(src.stops, greaterThan(0));
    expect(audio.muted, isFalse);
    // A late result from the cancelled recogniser is not delivered.
    src.streams[0].add(res('cat', 3));
    await settle();
    expect(got, isEmpty);
    expect(src.streams, hasLength(1));
  });

  test('cancelling the subscription restores audio too', () async {
    final sub = session
        .listenWhile(sessionId: 3, keepListening: () => true)
        .listen((_) {});
    await settle();
    await sub.cancel();
    await settle();
    expect(audio.muted, isFalse);
    expect(src.stops, greaterThan(0));
  });
}
