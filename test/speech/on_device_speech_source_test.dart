import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/speech/on_device_speech_source.dart';
import 'package:g_english_motion/speech/speech_source.dart';
import 'package:g_english_motion/speech/word_judge.dart';

class FakeBackend implements SpeechBackend {
  bool onDevice = true, permission = true, initOk = true;
  bool throwOnDeviceCheck = false;
  int initCalls = 0, listenCalls = 0, stopCalls = 0, onDeviceCalls = 0;
  String? lastLocale;
  void Function(List<String>, List<double>)? onResult;
  void Function()? onEnd;

  @override
  Future<bool> isOnDeviceAvailable() async {
    onDeviceCalls++;
    if (throwOnDeviceCheck) throw StateError('channel');
    return onDevice;
  }

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> initialize() async {
    initCalls++;
    return initOk && permission;
  }

  @override
  Future<void> listen({
    required String localeId,
    required void Function(List<String>, List<double>) onResult,
    required void Function() onEnd,
  }) async {
    listenCalls++;
    lastLocale = localeId;
    this.onResult = onResult;
    this.onEnd = onEnd;
  }

  @override
  Future<void> stop() async => stopCalls++;
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late FakeBackend b;
  late OnDeviceSpeechSource s;
  setUp(() {
    b = FakeBackend();
    s = OnDeviceSpeechSource(b);
  });

  group('check', () {
    test('available when on-device recogniser and permission exist', () async {
      expect(await s.check(), SpeechAvailability.available);
    });
    test('no on-device recogniser: never falls back, never asks mic', () async {
      b.onDevice = false;
      expect(await s.check(), SpeechAvailability.noOnDeviceRecognizer);
      expect(b.initCalls, 0);
    });
    test('mic denied -> noPermission', () async {
      b.permission = false;
      expect(await s.check(), SpeechAvailability.noPermission);
    });
    test(
      'init fails with permission granted -> noOnDeviceRecognizer',
      () async {
        b.initOk = false;
        expect(await s.check(), SpeechAvailability.noOnDeviceRecognizer);
      },
    );
    test('a throwing platform means unavailable, not a crash', () async {
      b.throwOnDeviceCheck = true;
      expect(await s.check(), SpeechAvailability.noOnDeviceRecognizer);
    });
  });

  group('listenOnce', () {
    test(
      'en_US, stamps the session id, ends when the recogniser ends',
      () async {
        final got = <RecognitionResult>[];
        final done = Completer<void>();
        s.listenOnce(sessionId: 42).listen(got.add, onDone: done.complete);
        await settle();
        expect(b.lastLocale, 'en_US');
        b.onResult!(['hand', 'and'], [0.9, 0.0]);
        await settle();
        expect(got.single.sessionId, 42);
        expect(got.single.transcripts, ['hand', 'and']);
        expect(got.single.confidences, [0.9, 0.0]);
        b.onEnd!();
        await done.future;
      },
    );

    test('refuses to listen unless on-device is available', () async {
      b.onDevice = false;
      final done = Completer<void>();
      final got = <RecognitionResult>[];
      final errors = <Object>[];
      s
          .listenOnce(sessionId: 1)
          .listen(got.add, onError: errors.add, onDone: done.complete);
      await done.future;
      expect(b.listenCalls, 0, reason: 'must not use a cloud recogniser');
      expect(got, isEmpty);
      expect(errors, hasLength(1));
    });

    test('a platform failure ends the stream with an error', () async {
      final errors = <Object>[];
      final done = Completer<void>();
      b.throwOnDeviceCheck = true;
      s
          .listenOnce(sessionId: 1)
          .listen((_) {}, onError: errors.add, onDone: done.complete);
      await done.future;
      expect(b.listenCalls, 0);
      expect(errors, hasLength(1));
    });

    test('a result of a finished listen is dropped', () async {
      final got = <RecognitionResult>[];
      s.listenOnce(sessionId: 1).listen(got.add);
      await settle();
      final stale = b.onResult!;
      b.onEnd!();
      await settle();
      stale(['hand'], [0.9]);
      await settle();
      expect(got, isEmpty);
    });

    test('cancelling the stream stops the recogniser', () async {
      final sub = s.listenOnce(sessionId: 1).listen((_) {});
      await settle();
      await sub.cancel();
      expect(b.stopCalls, greaterThan(0));
    });
  });

  test('plugin options enforce on-device recognition in en_US', () {
    final o = SpeechToTextBackend.listenOptions;
    expect(o.onDevice, isTrue);
    expect(o.localeId, 'en_US');
    expect(o.partialResults, isFalse);
    expect(o.cancelOnError, isTrue);
  });
}
