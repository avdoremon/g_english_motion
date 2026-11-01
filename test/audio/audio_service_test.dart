import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/audio/audio_service.dart';
import 'package:g_english_motion/audio/voice_lines.dart';
import 'package:g_english_motion/content/models.dart';

class FakeTts implements SpeechEngine {
  FakeTts(this.log, {this.hasVoice = true, this.throwOnSpeak = false});
  final List<String> log;
  bool hasVoice, throwOnSpeak, hang = false;
  Duration speakFor = Duration.zero;
  Completer<bool>? availGate;
  int availCalls = 0, active = 0, maxActive = 0;
  @override
  Future<bool> isEnglishAvailable() async {
    availCalls++;
    if (availGate != null) return availGate!.future;
    return hasVoice;
  }

  @override
  Future<void> speak(String text) async {
    log.add('tts:$text');
    if (throwOnSpeak) throw StateError('tts broken');
    if (hang) await Completer<void>().future;
    active++;
    if (active > maxActive) maxActive = active;
    await Future<void>.delayed(speakFor);
    active--;
    log.add('tts-end:$text');
  }

  @override
  Future<void> stop() async => log.add('tts.stop');
  @override
  Future<void> dispose() async => log.add('tts.dispose');
}

class FakeClips implements ClipPlayer {
  FakeClips(this.log, {this.result = true, this.throwOnPlay = false});
  final List<String> log;
  bool result, throwOnPlay, hang = false;
  @override
  Future<void> stop() async => log.add('clip.stop');
  @override
  Future<void> dispose() async => log.add('clip.dispose');
  @override
  Future<bool> play(String assetPath) async {
    log.add('clip:$assetPath');
    if (hang) await Completer<void>().future;
    if (throwOnPlay) throw StateError('clip broken');
    return result;
  }
}

const ball = ContentItem(
  id: 'g1u01-ball',
  word: 'ball',
  ttsText: 'ball',
  modes: [ModeKind.laneJump],
);

void main() {
  late List<String> log;
  late FakeTts tts;
  late FakeClips clips;
  late Set<String> existing;
  late AudioService svc;
  late List<String> captions;

  setUp(() {
    log = [];
    tts = FakeTts(log);
    clips = FakeClips(log);
    existing = {};
    svc = AudioService(
      tts,
      clips,
      assetExists: existing.contains,
      speechTimeout: const Duration(milliseconds: 50),
      clipTimeout: const Duration(milliseconds: 50),
    );
    captions = [];
    svc.captions.listen(captions.add);
  });

  test('recorded file exists -> clip played, TTS not called', () async {
    existing.add('assets/audio/en/g1u01-ball.m4a');
    await svc.sayEnglish('ball', itemId: 'g1u01-ball');
    expect(log, ['clip:assets/audio/en/g1u01-ball.m4a']);
    await Future<void>.delayed(Duration.zero);
    expect(captions, ['ball']);
  });

  test('no file, TTS has voice -> TTS called', () async {
    await svc.sayEnglish('ball', itemId: 'g1u01-ball');
    expect(log, ['tts:ball', 'tts-end:ball']);
  });

  test('no itemId -> TTS even if some file exists', () async {
    existing.add('assets/audio/en/g1u01-ball.m4a');
    await svc.sayEnglish('ball');
    expect(log, ['tts:ball', 'tts-end:ball']);
  });

  test('clip returns false -> falls back to TTS', () async {
    existing.add('assets/audio/en/g1u01-ball.m4a');
    clips.result = false;
    await svc.sayEnglish('ball', itemId: 'g1u01-ball');
    expect(log, [
      'clip:assets/audio/en/g1u01-ball.m4a',
      'tts:ball',
      'tts-end:ball',
    ]);
  });

  test('no file and no voice -> no throw, caption still emitted', () async {
    tts.hasVoice = false;
    await svc.sayEnglish('ball', itemId: 'g1u01-ball');
    await Future<void>.delayed(Duration.zero);
    expect(log, isEmpty);
    expect(captions, ['ball']);
  });

  test('engine throwing -> no throw, caption emitted', () async {
    tts.throwOnSpeak = true;
    await svc.sayEnglish('ball');
    await Future<void>.delayed(Duration.zero);
    expect(captions, ['ball']);
  });

  test('clip player throwing -> no throw, falls back to TTS', () async {
    existing.add('assets/audio/en/g1u01-ball.m4a');
    clips.throwOnPlay = true;
    await svc.sayEnglish('ball', itemId: 'g1u01-ball');
    expect(log.last, 'tts-end:ball');
  });

  test('isEnglishAvailable throwing -> no throw', () async {
    final bad = AudioService(
      _ThrowingAvail(),
      clips,
      assetExists: existing.contains,
    );
    await bad.sayEnglish('ball');
  });

  test('playLine with asset -> clip and Vietnamese caption', () async {
    existing.add('assets/audio/vi/welcome.m4a');
    await svc.playLine(VoiceLine.welcome);
    await Future<void>.delayed(Duration.zero);
    expect(log, ['clip:assets/audio/vi/welcome.m4a']);
    expect(captions, ['Chào mừng em! Hãy đứng trước camera nhé']);
  });

  test('playLine without asset -> caption only, completes', () async {
    await svc.playLine(VoiceLine.tryAgain);
    await Future<void>.delayed(Duration.zero);
    expect(log, isEmpty);
    expect(captions, ['Chưa đúng rồi, thử lại nhé!']);
  });

  test('playLine clip throwing -> no throw', () async {
    existing.add('assets/audio/vi/welcome.m4a');
    clips.throwOnPlay = true;
    await svc.playLine(VoiceLine.welcome);
  });

  test('explainAnswer plays theAnswerIs then the English word', () async {
    existing.add('assets/audio/vi/theAnswerIs.m4a');
    await svc.explainAnswer(ball);
    expect(log, [
      'clip:assets/audio/vi/theAnswerIs.m4a',
      'tts:ball',
      'tts-end:ball',
    ]);
  });

  test('muted -> captions only, no audio', () async {
    existing.add('assets/audio/en/g1u01-ball.m4a');
    existing.add('assets/audio/vi/welcome.m4a');
    svc.muteForListening();
    expect(svc.muted, isTrue);
    await svc.sayEnglish('ball', itemId: 'g1u01-ball');
    await svc.playLine(VoiceLine.welcome);
    await Future<void>.delayed(Duration.zero);
    expect(log, ['tts.stop', 'clip.stop']); // only the stops, no playback
    expect(captions, ['ball', 'Chào mừng em! Hãy đứng trước camera nhé']);
    svc.restoreAfterListening();
    expect(svc.muted, isFalse);
    log.clear();
    await svc.sayEnglish('ball');
    expect(log, ['tts:ball', 'tts-end:ball']);
  });

  test('caption is emitted BEFORE the audio call', () async {
    existing.add('assets/audio/en/g1u01-ball.m4a');
    svc.captions.listen((c) => log.add('cap:$c'));
    await svc.sayEnglish('ball', itemId: 'g1u01-ball');
    expect(log.take(2), ['cap:ball', 'clip:assets/audio/en/g1u01-ball.m4a']);
  });

  test('hanging TTS completes after the timeout, no throw', () async {
    tts.hang = true;
    await svc.sayEnglish('ball').timeout(const Duration(seconds: 2));
    expect(log, contains('tts.stop'));
  });

  test('hanging clip falls back to TTS', () async {
    existing.add('assets/audio/en/g1u01-ball.m4a');
    clips.hang = true;
    await svc
        .sayEnglish('ball', itemId: 'g1u01-ball')
        .timeout(const Duration(seconds: 2));
    expect(log, contains('tts:ball'));
  });

  test('concurrent calls play in order and never overlap', () async {
    tts.speakFor = const Duration(milliseconds: 20);
    final a = svc.sayEnglish('one');
    final b = svc.sayEnglish('two');
    await Future.wait([a, b]);
    expect(log, ['tts:one', 'tts-end:one', 'tts:two', 'tts-end:two']);
    expect(tts.maxActive, 1);
  });

  test(
    'mute during in-flight utterance completes promptly and stops',
    () async {
      tts.speakFor = const Duration(seconds: 5);
      final f = svc.sayEnglish('ball');
      final queued = svc.sayEnglish('two');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      svc.muteForListening();
      await Future.wait([f, queued]).timeout(const Duration(seconds: 1));
      expect(log, containsAll(['tts.stop', 'clip.stop']));
      expect(log.where((e) => e == 'tts:two'), isEmpty);
    },
  );

  test('mute during isEnglishAvailable await -> no speak', () async {
    tts.availGate = Completer<bool>();
    final f = svc.sayEnglish('ball');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    svc.muteForListening();
    tts.availGate!.complete(true);
    await f;
    expect(log.where((e) => e.startsWith('tts:')), isEmpty);
  });

  test('positive availability is cached', () async {
    await svc.sayEnglish('a');
    await svc.sayEnglish('b');
    expect(tts.availCalls, 1);
  });

  test('dispose disposes engine and player', () async {
    await svc.dispose();
    expect(log, containsAll(['tts.dispose', 'clip.dispose']));
  });

  test('after dispose: no engine calls, no throw', () async {
    await svc.dispose();
    log.clear();
    await svc.sayEnglish('ball');
    await svc.playLine(VoiceLine.welcome);
    svc.muteForListening();
    expect(log, isEmpty);
  });

  test('dispose does not hang on a hung engine dispose', () async {
    final hung = AudioService(
      _HangDispose(),
      clips,
      assetExists: existing.contains,
    );
    await hung.dispose().timeout(const Duration(seconds: 4));
  });

  test('every VoiceLine has asset path and caption', () {
    for (final l in VoiceLine.values) {
      expect(l.assetPath, 'assets/audio/vi/${l.name}.m4a');
      expect(l.caption, isNotEmpty);
    }
    expect(VoiceLine.values.length, 14);
  });

  test('captions is a broadcast stream', () {
    expect(svc.captions.isBroadcast, isTrue);
  });
}

class _ThrowingAvail implements SpeechEngine {
  @override
  Future<bool> isEnglishAvailable() async => throw StateError('x');
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _HangDispose implements SpeechEngine {
  @override
  Future<bool> isEnglishAvailable() async => true;
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() => Completer<void>().future;
}
