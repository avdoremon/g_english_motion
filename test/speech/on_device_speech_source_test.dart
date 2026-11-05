import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/speech/on_device_speech_source.dart';
import 'package:g_english_motion/speech/speech_source.dart';
import 'package:g_english_motion/speech/word_judge.dart';
import 'package:speech_to_text/speech_to_text.dart';

class _FakeStt implements SpeechToText {
  SpeechStatusListener? onStatus;
  int cancels = 0;
  bool listening = true;

  @override
  bool get isListening => listening;

  @override
  Future<bool> initialize({
    SpeechErrorListener? onError,
    SpeechStatusListener? onStatus,
    debugLogging = false,
    Duration finalTimeout = SpeechToText.defaultFinalTimeout,
    List<SpeechConfigOption>? options,
  }) async {
    this.onStatus = onStatus;
    return true;
  }

  @override
  Future listen({
    SpeechResultListener? onResult,
    Duration? listenFor,
    Duration? pauseFor,
    String? localeId,
    SpeechSoundLevelChange? onSoundLevelChange,
    cancelOnError = false,
    partialResults = true,
    onDevice = false,
    ListenMode listenMode = ListenMode.confirmation,
    sampleRate = 0,
    SpeechListenOptions? listenOptions,
  }) async {}

  @override
  Future<void> cancel() async => cancels++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeBackend implements SpeechBackend {
  bool onDevice = true, permission = true, initOk = true, grantOnAsk = true;
  bool throwOnDeviceCheck = false;

  /// Whether [listen] reports that the recogniser actually started.
  bool startOk = true;

  @override
  Duration listenTimeout = const Duration(milliseconds: 40);

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
  Future<bool> listen({
    required String localeId,
    required void Function(List<String>, List<double>) onResult,
    required void Function(String? errorCode) onEnd,
  }) async {
    listenCalls++;
    lastLocale = localeId;
    this.onResult = onResult;
    this.onEnd = onEnd;
    return startOk;
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

    test('a listen that never starts fails, it is not silence', () async {
      // The plugin answers false (and calls nothing back) when it thinks it
      // is still listening: "heard nothing" would mark the word wrong.
      b.startOk = false;
      final errors = <Object>[];
      final done = Completer<void>();
      s
          .listenOnce(sessionId: 1)
          .listen((_) {}, onError: errors.add, onDone: done.complete);
      await done.future;
      expect(errors, hasLength(1));
      expect(errors.single.toString(), contains(speechNotStartedError));
    });

    test('a listen that starts and never ends fails after the '
        'watchdog', () async {
      final errors = <Object>[];
      final done = Completer<void>();
      s
          .listenOnce(sessionId: 1)
          .listen((_) {}, onError: errors.add, onDone: done.complete);
      await settle();
      expect(b.listenCalls, 1);
      expect(errors, isEmpty, reason: 'still within the watchdog');
      await done.future.timeout(const Duration(seconds: 5));
      expect(errors, hasLength(1));
      expect(errors.single.toString(), contains(speechNotStartedError));
    });

    test('the watchdog is dropped when the listen ends normally', () async {
      final errors = <Object>[];
      final done = Completer<void>();
      s
          .listenOnce(sessionId: 1)
          .listen((_) {}, onError: errors.add, onDone: done.complete);
      await settle();
      b.onEnd!(null);
      await done.future;
      await Future<void>.delayed(b.listenTimeout * 3);
      expect(errors, isEmpty);
    });

    test('the recogniser is stopped before every listen', () async {
      final done = Completer<void>();
      s.listenOnce(sessionId: 1).listen((_) {}, onDone: done.complete);
      await settle();
      expect(
        b.stopCalls,
        greaterThanOrEqualTo(1),
        reason: 'a recogniser left running holds the microphone',
      );
      b.onEnd!(null);
      await done.future;
      final stopsAfterFirst = b.stopCalls;
      s.listenOnce(sessionId: 2).listen((_) {});
      await settle();
      expect(b.stopCalls, greaterThan(stopsAfterFirst));
      await s.stop();
    });

    test('benign error codes', () {
      expect(isBenignSpeechError('error_no_match'), isTrue);
      expect(isBenignSpeechError('error_speech_timeout'), isTrue);
      expect(isBenignSpeechError('error_busy'), isFalse);
      expect(isBenignSpeechError('error_permission'), isFalse);
    });
  });

  test('a late done after stop() reaches no callback; the next listen ends normally', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = MethodChannel(SpeechToTextBackend.channelName);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => true);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
    final stt = _FakeStt();
    final b = SpeechToTextBackend(plugin: stt, channel: channel);
    await b.isOnDeviceAvailable();
    await b.initialize();
    final ends = <String>[];
    await b.listen(
      localeId: 'en_US',
      onResult: (_, _) {},
      onEnd: (c) => ends.add('first:$c'),
    );
    await b.stop();
    expect(stt.cancels, 1);
    stt.onStatus!(SpeechToText.doneStatus); // late, from the cancelled listen
    expect(ends, isEmpty, reason: 'a cancelled listen is never reported');
    await b.listen(
      localeId: 'en_US',
      onResult: (_, _) {},
      onEnd: (c) => ends.add('second:$c'),
    );
    stt.onStatus!(SpeechToText.doneStatus);
    expect(ends, ['second:null']);
  });

  test('plugin options enforce on-device recognition in en_US', () {
    final o = SpeechToTextBackend.listenOptions;
    expect(o.onDevice, isTrue);
    expect(o.localeId, 'en_US');
    expect(o.partialResults, isFalse);
    expect(o.cancelOnError, isTrue);
  });
}
