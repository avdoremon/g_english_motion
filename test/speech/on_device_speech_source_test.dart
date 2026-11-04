import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/speech/on_device_speech_source.dart';
import 'package:g_english_motion/speech/speech_source.dart';
import 'package:g_english_motion/speech/word_judge.dart';

class FakeBackend implements SpeechBackend {
  bool onDevice = true, permission = true, initOk = true, grantOnAsk = true;
  bool throwOnDeviceCheck = false;
  int initCalls = 0, listenCalls = 0, stopCalls = 0, onDeviceCalls = 0;
  int requests = 0;
  String? lastLocale;
  void Function(List<String>, List<double>)? onResult;
  void Function(String?)? onEnd;

  @override
  Future<bool> isOnDeviceAvailable() async {
    onDeviceCalls++;
    if (throwOnDeviceCheck) throw StateError('channel');
    return onDevice;
  }

  @override
  Future<bool> hasPermission() async => permission;

  @override
  Future<bool> requestPermission() async {
    requests++;
    if (grantOnAsk) permission = true;
    return permission;
  }

  @override
  Future<bool> initialize() async {
    initCalls++;
    return initOk;
  }

  @override
  Future<void> listen({
    required String localeId,
    required void Function(List<String>, List<double>) onResult,
    required void Function(String? errorCode) onEnd,
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
    test(
      'available when on-device recogniser and mic already granted',
      () async {
        expect(await s.check(), SpeechAvailability.available);
        expect(
          b.initCalls,
          0,
          reason: 'the plugin is not initialised by check',
        );
        expect(b.requests, 0);
      },
    );
    test('no on-device recogniser: never falls back, never asks mic', () async {
      b.onDevice = false;
      expect(
        await s.check(askPermission: true),
        SpeechAvailability.noOnDeviceRecognizer,
      );
      expect(b.requests, 0);
    });
    test('mic not granted: noPermission and NO prompt by default', () async {
      b.permission = false;
      expect(await s.check(), SpeechAvailability.noPermission);
      expect(b.requests, 0);
      expect(b.initCalls, 0);
    });
    test('askPermission requests the mic; granted -> available', () async {
      b.permission = false;
      expect(await s.check(askPermission: true), SpeechAvailability.available);
      expect(b.requests, 1);
    });
    test('askPermission refused -> noPermission', () async {
      b.permission = false;
      b.grantOnAsk = false;
      expect(
        await s.check(askPermission: true),
        SpeechAvailability.noPermission,
      );
    });
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
        b.onEnd!(null);
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
      b.onEnd!(null);
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

  group('listen errors', () {
    Future<(List<Object>, bool)> run() async {
      final errors = <Object>[];
      final done = Completer<void>();
      s
          .listenOnce(sessionId: 1)
          .listen((_) {}, onError: errors.add, onDone: done.complete);
      await settle();
      return (errors, done.isCompleted);
    }

    test('no_match and speech_timeout end the stream normally', () async {
      for (final code in ['error_no_match', 'error_speech_timeout']) {
        b = FakeBackend();
        s = OnDeviceSpeechSource(b);
        final (errors, _) = await run();
        b.onEnd!(code);
        await settle();
        expect(errors, isEmpty, reason: code);
      }
    });

    test(
      'permission, language, busy, audio errors surface as errors',
      () async {
        for (final code in [
          'error_permission',
          'error_language_unavailable',
          'error_language_not_supported',
          'error_busy',
          'error_audio',
          'error_network',
        ]) {
          b = FakeBackend();
          s = OnDeviceSpeechSource(b);
          final (errors, _) = await run();
          b.onEnd!(code);
          await settle();
          expect(errors, hasLength(1), reason: code);
        }
      },
    );

    test('a failing initialise is an error and never listens', () async {
      b.initOk = false;
      final (errors, _) = await run();
      expect(errors, hasLength(1));
      expect(b.listenCalls, 0);
    });

    test('the plugin is initialised once, on the first listen', () async {
      await run();
      b.onEnd!(null);
      await run();
      expect(b.initCalls, 1);
    });

    test('benign error codes', () {
      expect(isBenignSpeechError('error_no_match'), isTrue);
      expect(isBenignSpeechError('error_speech_timeout'), isTrue);
      expect(isBenignSpeechError('error_busy'), isFalse);
      expect(isBenignSpeechError('error_permission'), isFalse);
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
