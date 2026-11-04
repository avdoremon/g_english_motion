import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/app/app.dart';
import 'package:g_english_motion/audio/audio_service.dart';
import 'package:g_english_motion/content/content_repository.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/input/pose_frame_source.dart';
import 'package:g_english_motion/modes/say_it.dart';
import 'package:g_english_motion/progress/progress_store.dart';
import 'package:g_english_motion/speech/speech_session.dart';
import 'package:g_english_motion/speech/speech_source.dart';
import 'package:g_english_motion/speech/word_judge.dart';
import 'package:g_english_motion/ui/mascot/tin_tin.dart';
import 'package:g_english_motion/ui/screens/say_it_screen.dart';
import 'package:g_english_motion/ui/shell/game_shell.dart';
import 'package:g_english_motion/ui/shell/pose_camera_host.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/game_harness.dart';

class GateTts implements SpeechEngine {
  final List<String> spoken = [];
  Completer<void>? gate;
  @override
  Future<bool> isEnglishAvailable() async => true;
  @override
  Future<void> speak(String text) async {
    spoken.add(text);
    await gate?.future;
  }

  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class NoClips implements ClipPlayer {
  @override
  Future<bool> play(String assetPath) async => false;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class FakeSource implements SpeechSource {
  FakeSource({this.availability = SpeechAvailability.available});
  SpeechAvailability availability;
  bool fail = false;
  final List<int> ids = [];
  final List<StreamController<RecognitionResult>> streams = [];
  int checks = 0;

  @override
  Future<SpeechAvailability> check() async {
    checks++;
    return availability;
  }

  @override
  Stream<RecognitionResult> listenOnce({required int sessionId}) {
    ids.add(sessionId);
    if (fail) return Stream.error(StateError('mic'));
    final c = StreamController<RecognitionResult>();
    streams.add(c);
    return c.stream;
  }

  /// Says [w] to the most recent listen.
  void hear(String w, {int? id}) => streams.last.add(
    RecognitionResult(transcripts: [w], sessionId: id ?? ids.last),
  );

  @override
  Future<void> stop() async {}
}

ContentItem item(String w) => ContentItem(
  id: 'g3-$w',
  word: w,
  ttsText: w,
  modes: const [ModeKind.sayIt],
);

const words = [
  'cat', 'dog', 'hand', 'book', 'pen', 'bag', 'cup', 'hat', 'sun', //
];
const travel = Duration(seconds: 10);

/// A level whose very first word moves as [motion].
SayItLevel levelWith(WordMotion motion, {bool modelFirst = false}) {
  for (var seed = 0; seed < 100; seed++) {
    final l = SayItLevel.build(
      [for (final w in words) item(w)],
      travelTime: travel,
      rng: Random(seed),
      modelFirst: modelFirst,
      firstSessionId: 1,
    );
    if (l.rounds.first.current.motion == motion) return l;
  }
  throw StateError('no seed');
}

/// The screen caps one clock step at 250 ms, so time is advanced in small
/// steps like real frames.
Future<void> advance(WidgetTester t, Duration d) async {
  const step = Duration(milliseconds: 100);
  var left = d;
  while (left > Duration.zero) {
    final s = left < step ? left : step;
    await t.pump(s);
    left -= s;
  }
}

void main() {
  late FakeSource src;
  late GateTts tts;
  late AudioService audio;
  late SpeechSession session;

  Future<void> pumpScreen(WidgetTester tester, SayItLevel level) async {
    src = FakeSource();
    tts = GateTts();
    audio = AudioService(tts, NoClips(), assetExists: (_) => false);
    session = SpeechSession(src, audio, relistenDelay: Duration.zero);
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: SayItScreen(
          level: level,
          speech: session,
          audio: audio,
          onExit: () {},
          onPlayAgain: () {},
        ),
      ),
    );
    await tester.pump();
    await advance(tester, const Duration(milliseconds: 20));
  }

  final word = find.byKey(const ValueKey('say-it-word'));
  final verdict = find.byKey(const ValueKey('say-it-verdict'));
  final explosion = find.byKey(const ValueKey('say-it-explosion'));
  Finder tin(TinTinState s) =>
      find.byWidgetPredicate((w) => w is TinTin && w.state == s);

  testWidgets('a falling word moves down and keeps its column', (t) async {
    await pumpScreen(t, levelWith(WordMotion.fallDown));
    final a = t.getCenter(word);
    await advance(t, const Duration(seconds: 3));
    final b = t.getCenter(word);
    expect(b.dy, greaterThan(a.dy + 50));
    expect(b.dx, closeTo(a.dx, 0.5));
  });

  testWidgets('a right-to-left word moves left and keeps its row', (t) async {
    await pumpScreen(t, levelWith(WordMotion.rightToLeft));
    final a = t.getCenter(word);
    await advance(t, const Duration(seconds: 3));
    final b = t.getCenter(word);
    expect(b.dx, lessThan(a.dx - 100));
    expect(b.dy, closeTo(a.dy, 0.5));
  });

  testWidgets('listens while the word runs; sound is muted meanwhile', (
    t,
  ) async {
    await pumpScreen(t, levelWith(WordMotion.fallDown));
    expect(src.ids, [1]);
    expect(audio.muted, isTrue);
  });

  testWidgets('correct: Đúng with an icon, happy Tin Tin, then the burst', (
    t,
  ) async {
    await pumpScreen(t, levelWith(WordMotion.fallDown));
    await advance(t, const Duration(seconds: 1));
    src.hear('cat');
    await t.pump();
    expect(
      find.descendant(of: verdict, matching: find.text('Đúng')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: verdict, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
    expect(tin(TinTinState.happy), findsOneWidget);
    expect(explosion, findsNothing);
    expect(audio.muted, isFalse, reason: 'sound is back once judged');
    await advance(t, kJudgedHold);
    await advance(t, const Duration(milliseconds: 16));
    expect(verdict, findsNothing);
    expect(explosion, findsOneWidget);
    expect(word, findsNothing);
    await advance(t, const Duration(milliseconds: 400));
    expect(explosion, findsOneWidget);
    await advance(t, const Duration(milliseconds: 400));
    await advance(t, const Duration(milliseconds: 20));
    // The next word is on its way (new listen with the next session id).
    expect(explosion, findsNothing);
    expect(word, findsOneWidget);
    expect(find.text('dog'), findsOneWidget);
    expect(src.ids.last, 2);
  });

  testWidgets('wrong: Sai with an icon and a sad Tin Tin', (t) async {
    await pumpScreen(t, levelWith(WordMotion.rightToLeft));
    src.hear('hat');
    await t.pump();
    expect(
      find.descendant(of: verdict, matching: find.text('Sai')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: verdict, matching: find.byIcon(Icons.cancel)),
      findsOneWidget,
    );
    expect(tin(TinTinState.sad), findsOneWidget);
  });

  testWidgets('a result tagged with another word is ignored', (t) async {
    await pumpScreen(t, levelWith(WordMotion.fallDown));
    src.hear('cat', id: 99);
    await t.pump();
    expect(verdict, findsNothing);
  });

  testWidgets('no answer: not wrong until the grace after the run is over', (
    t,
  ) async {
    await pumpScreen(t, levelWith(WordMotion.fallDown));
    for (var i = 0; i < 10; i++) {
      await advance(t, const Duration(seconds: 1));
    }
    expect(verdict, findsNothing, reason: 'run just ended, grace not over');
    await advance(t, const Duration(milliseconds: 500));
    await advance(t, const Duration(milliseconds: 600));
    expect(
      find.descendant(of: verdict, matching: find.text('Sai')),
      findsOneWidget,
    );
  });

  testWidgets('nine correct words end on the result with 3 stars; no word', (
    t,
  ) async {
    await pumpScreen(t, levelWith(WordMotion.fallDown));
    for (final w in words) {
      src.hear(w);
      await t.pump();
      await advance(t, kJudgedHold);
      await advance(t, kExplosionTime);
      await advance(t, const Duration(milliseconds: 50));
    }
    expect(word, findsNothing);
    expect(explosion, findsNothing);
    expect(find.byKey(const ValueKey('say-it-total')), findsOneWidget);
    expect(find.text('Đúng 9/9 từ'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('say-it-stars')),
        matching: find.byIcon(Icons.star),
      ),
      findsNWidgets(3),
    );
    expect(audio.muted, isFalse);
  });

  testWidgets(
    'grades 1-2: the model reads first; the word waits and then runs',
    (t) async {
      tts = GateTts()..gate = Completer<void>();
      final level = levelWith(WordMotion.fallDown, modelFirst: true);
      src = FakeSource();
      audio = AudioService(tts, NoClips(), assetExists: (_) => false);
      session = SpeechSession(src, audio, relistenDelay: Duration.zero);
      await t.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => t.binding.setSurfaceSize(null));
      await t.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: SayItScreen(
            level: level,
            speech: session,
            audio: audio,
            onExit: () {},
          ),
        ),
      );
      await t.pump();
      await advance(t, const Duration(milliseconds: 20));
      expect(tts.spoken, ['cat']);
      final a = t.getCenter(word);
      await advance(t, const Duration(seconds: 3));
      expect(t.getCenter(word), a, reason: 'not moving while the model reads');
      expect(src.ids, isEmpty, reason: 'the microphone is closed');
      expect(audio.muted, isFalse);
      tts.gate!.complete();
      await t.pump();
      await advance(t, const Duration(milliseconds: 20));
      expect(src.ids, [1]);
      await advance(t, const Duration(seconds: 3));
      expect(t.getCenter(word).dy, greaterThan(a.dy + 50));
    },
  );

  testWidgets('a failing microphone pauses with a message, never "Sai"', (
    t,
  ) async {
    src = FakeSource()..fail = true;
    tts = GateTts();
    audio = AudioService(tts, NoClips(), assetExists: (_) => false);
    session = SpeechSession(src, audio, relistenDelay: Duration.zero);
    await t.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: SayItScreen(
          level: levelWith(WordMotion.fallDown),
          speech: session,
          audio: audio,
          onExit: () {},
        ),
      ),
    );
    await t.pump();
    await advance(t, const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('say-it-mic-problem')), findsOneWidget);
    for (var i = 0; i < 15; i++) {
      await advance(t, const Duration(seconds: 1));
    }
    expect(verdict, findsNothing);
    expect(audio.muted, isFalse);
  });

  group('in the app', () {
    late ProgressStore store;
    late FakeSource speech;
    late int sources;
    late List<String> ttsLog;

    Future<void> pumpApp(
      WidgetTester tester, {
      SpeechAvailability availability = SpeechAvailability.available,
      bool sayItOn = true,
    }) async {
      SharedPreferences.setMockInitialValues({
        'progress.safetyAck': true,
        'progress.sayIt': sayItOn,
      });
      store = ProgressStore(await SharedPreferences.getInstance());
      speech = FakeSource(availability: availability);
      sources = 0;
      ttsLog = [];
      final a = AudioService(
        HarnessTts(ttsLog),
        HarnessClips(),
        assetExists: (_) => false,
      );
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        GEnglishMotionApp(
          deps: AppDependencies(
            store: store,
            audio: a,
            repo: ContentRepository([
              harnessUnit(modes: const [ModeKind.laneJump, ModeKind.sayIt]),
            ]),
            levels: const [harnessLevel],
            sourceFactory: () {
              sources++;
              return FakePoseFrameSource.fromStream(
                const Stream<Never>.empty(),
              );
            },
            ticker: () => const Stream<Duration>.empty(),
            wakelock: _NoWakelock(),
            speech: speech,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
    }

    final entry = find.byKey(const ValueKey('sayit-entry'));

    testWidgets('SayIt starts without any camera or pose tracking', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await tester.pump();
      await advance(tester, const Duration(milliseconds: 50));
      expect(find.byType(SayItScreen), findsOneWidget);
      expect(sources, 0, reason: 'no pose source was created');
      expect(find.byType(GameShell), findsNothing);
      expect(find.byType(PoseCameraHost), findsNothing);
      expect(speech.ids, isNotEmpty, reason: 'the microphone is open');
      await tester.tap(find.byKey(const ValueKey('exit')));
      await tester.pump();
      expect(find.byType(SayItScreen), findsNothing);
      expect(find.byKey(const ValueKey('play')), findsOneWidget);
    });

    testWidgets('grade 1 hears the model word before it runs', (tester) async {
      await pumpApp(tester);
      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final shown = tester
          .widget<Text>(
            find.descendant(
              of: find.byKey(const ValueKey('say-it-word')),
              matching: find.byType(Text),
            ),
          )
          .data;
      expect(ttsLog.first, 'tts:$shown');
    });

    testWidgets('entry stays hidden when check() is not available', (
      tester,
    ) async {
      for (final a in [
        SpeechAvailability.noPermission,
        SpeechAvailability.noOnDeviceRecognizer,
      ]) {
        await pumpApp(tester, availability: a);
        expect(entry, findsNothing, reason: '$a');
      }
    });

    testWidgets('entry stays hidden when the parent switched SayIt off', (
      tester,
    ) async {
      await pumpApp(tester, sayItOn: false);
      expect(entry, findsNothing);
      expect(speech.checks, 0, reason: 'no microphone question when off');
    });
  });
}

class _NoWakelock implements Wakelock {
  @override
  Future<void> enable() async {}
  @override
  Future<void> disable() async {}
}
