import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/audio/audio_service.dart';
import 'package:g_english_motion/audio/voice_lines.dart';
import 'package:g_english_motion/content/models.dart';

class FakeTts implements SpeechEngine {
  FakeTts(this.log, {this.hasVoice = true, this.throwOnSpeak = false});
  final List<String> log;
  bool hasVoice, throwOnSpeak;
  @override
  Future<bool> isEnglishAvailable() async => hasVoice;
  @override
  Future<void> speak(String text) async {
    log.add('tts:$text');
    if (throwOnSpeak) throw StateError('tts broken');
  }
}

class FakeClips implements ClipPlayer {
  FakeClips(this.log, {this.result = true, this.throwOnPlay = false});
  final List<String> log;
  bool result, throwOnPlay;
  @override
  Future<bool> play(String assetPath) async {
    log.add('clip:$assetPath');
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
    svc = AudioService(tts, clips, assetExists: existing.contains);
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
    expect(log, ['tts:ball']);
  });

  test('no itemId -> TTS even if some file exists', () async {
    existing.add('assets/audio/en/g1u01-ball.m4a');
    await svc.sayEnglish('ball');
    expect(log, ['tts:ball']);
  });

  test('clip returns false -> falls back to TTS', () async {
    existing.add('assets/audio/en/g1u01-ball.m4a');
    clips.result = false;
    await svc.sayEnglish('ball', itemId: 'g1u01-ball');
    expect(log, ['clip:assets/audio/en/g1u01-ball.m4a', 'tts:ball']);
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
    expect(log.last, 'tts:ball');
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
    expect(captions, ['Chào mừng bạn! Hãy đứng trước camera nhé']);
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
    expect(log, ['clip:assets/audio/vi/theAnswerIs.m4a', 'tts:ball']);
  });

  test('muted -> captions only, no audio', () async {
    existing.add('assets/audio/en/g1u01-ball.m4a');
    existing.add('assets/audio/vi/welcome.m4a');
    svc.muteForListening();
    expect(svc.muted, isTrue);
    await svc.sayEnglish('ball', itemId: 'g1u01-ball');
    await svc.playLine(VoiceLine.welcome);
    await Future<void>.delayed(Duration.zero);
    expect(log, isEmpty);
    expect(captions, ['ball', 'Chào mừng bạn! Hãy đứng trước camera nhé']);
    svc.restoreAfterListening();
    expect(svc.muted, isFalse);
    await svc.sayEnglish('ball');
    expect(log, ['tts:ball']);
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
}
