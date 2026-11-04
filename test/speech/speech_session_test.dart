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

class FakeSource implements SpeechSource {
  FakeSource(this.log);
  final List<String> log;
  final List<StreamController<RecognitionResult>> streams = [];
  final List<int> ids = [];
  Object? failWith;
  int stops = 0;

  @override
  Future<SpeechAvailability> check() async => SpeechAvailability.available;

  @override
  Stream<RecognitionResult> listenOnce({required int sessionId}) {
    log.add('listen');
    ids.add(sessionId);
    if (failWith != null) return Stream.error(failWith!);
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

  test('a throwing source restores audio and does not throw', () async {
    src.failWith = StateError('boom');
    final errors = <Object>[];
    final done = Completer<void>();
    session
        .listenWhile(sessionId: 1, keepListening: () => true)
        .listen((_) {}, onError: errors.add, onDone: done.complete);
    await done.future;
    expect(errors, isEmpty);
    expect(log, containsAllInOrder(['mute', 'listen', 'restore']));
    expect(src.streams, isEmpty, reason: 'no retry storm after a failure');
    expect(session.failed, isTrue);
    expect(audio.muted, isFalse);
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
