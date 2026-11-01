import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/audio/audio_service.dart';

class FakeTtsBackend implements TtsBackend {
  final log = <String>[];
  Completer<void>? langGate;
  @override
  Future<bool> isLanguageAvailable(String lang) async => true;
  @override
  Future<void> setLanguage(String lang) async {
    log.add('lang');
    if (langGate != null) await langGate!.future;
  }

  @override
  Future<void> awaitCompletion(bool v) async => log.add('await');
  @override
  Future<void> speak(String t) async => log.add('speak:$t');
  @override
  Future<void> stop() async => log.add('stop');
}

class FakeAudioBackend implements AudioBackend {
  final log = <String>[];
  Completer<void>? assetGate;
  @override
  bool completed = true;
  @override
  Future<void> setAsset(String p) async {
    log.add('setAsset');
    if (assetGate != null) await assetGate!.future;
  }

  @override
  Future<void> play() async => log.add('play');
  @override
  Future<void> stop() async => log.add('stop');
  @override
  Future<void> dispose() async => log.add('dispose');
}

void main() {
  test('TTS: normal speak reaches backend', () async {
    final b = FakeTtsBackend();
    await FlutterTtsEngine(backend: b).speak('ball');
    expect(b.log, ['lang', 'await', 'speak:ball']);
  });

  test('TTS: stop during setLanguage -> native speak never called', () async {
    final b = FakeTtsBackend()..langGate = Completer();
    final e = FlutterTtsEngine(backend: b);
    final f = e.speak('ball');
    await Future<void>.delayed(Duration.zero);
    await e.stop();
    b.langGate!.complete();
    await f;
    expect(b.log.where((x) => x.startsWith('speak')), isEmpty);
  });

  test('Clip: normal play returns true', () async {
    final b = FakeAudioBackend();
    expect(await JustAudioClipPlayer(backend: b).play('a'), isTrue);
    expect(b.log, ['setAsset', 'play']);
  });

  test('Clip: not completed -> false', () async {
    final b = FakeAudioBackend()..completed = false;
    expect(await JustAudioClipPlayer(backend: b).play('a'), isFalse);
  });

  test('Clip: stop during setAsset -> play() never called', () async {
    final b = FakeAudioBackend()..assetGate = Completer();
    final p = JustAudioClipPlayer(backend: b);
    final f = p.play('a');
    await Future<void>.delayed(Duration.zero);
    await p.stop();
    b.assetGate!.complete();
    expect(await f, isFalse);
    expect(b.log, ['setAsset', 'stop']);
  });
}
