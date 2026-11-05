import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel, rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/app/app.dart';
import 'package:g_english_motion/app/game_controller.dart';
import 'package:g_english_motion/audio/audio_service.dart';
import 'package:g_english_motion/audio/voice_lines.dart';
import 'package:g_english_motion/content/content_repository.dart';
import 'package:g_english_motion/content/models.dart' show ModeKind;
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/input/plugin_pose_frame_source.dart';
import 'package:g_english_motion/input/pose_frame_source.dart';
import 'package:g_english_motion/input/pose_types.dart';
import 'package:g_english_motion/levels/level_config.dart';
import 'package:g_english_motion/progress/progress_store.dart';
import 'package:g_english_motion/session/level_session.dart';
import 'package:g_english_motion/speech/speech_source.dart';
import 'package:g_english_motion/speech/word_judge.dart';
import 'package:g_english_motion/ui/screens/say_it_screen.dart';
import 'package:g_english_motion/ui/shell/game_shell.dart';
import 'package:g_english_motion/ui/shell/pose_camera_host.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/capture_print.dart';
import '../helpers/game_harness.dart';
import '../helpers/synthetic_poses.dart';

class _NoWakelock implements Wakelock {
  _NoWakelock();
  final log = <String>[];
  @override
  Future<void> enable() async => log.add('enable');
  @override
  Future<void> disable() async => log.add('disable');
}

/// On-device speech that answers whatever the test wants, and records every
/// availability check (and whether it asked the OS for the microphone).
class _FakeSpeech implements SpeechSource {
  _FakeSpeech({this.availability = SpeechAvailability.available});
  SpeechAvailability availability;
  int checks = 0, asked = 0, cancels = 0;
  final List<int> ids = [];
  final List<StreamController<RecognitionResult>> streams = [];

  @override
  Future<SpeechAvailability> check({bool askPermission = false}) async {
    checks++;
    if (askPermission) asked++;
    return availability;
  }

  @override
  Stream<RecognitionResult> listenOnce({required int sessionId}) {
    ids.add(sessionId);
    final c = StreamController<RecognitionResult>();
    streams.add(c);
    return c.stream;
  }

  @override
  Future<void> stop() async => cancels++;
}

class _ThrowingStart extends GameController {
  _ThrowingStart({
    required super.grade,
    required super.level,
    required super.store,
    required super.repo,
    required super.audio,
    required super.ticker,
  });

  @override
  Future<PermissionOutcome> start(PoseFrameSource source) =>
      Future.error(StateError('boom'));
}

void main() {
  late ProgressStore store;
  late FakePoseFrameSource source;
  late List<String> captions;
  late _NoWakelock wakelock;

  Future<void> pumpApp(
    WidgetTester tester, {
    bool content = true,
    ContentRepository? repo,
    bool safetyAcked = true,
    PermissionOutcome permission = PermissionOutcome.granted,
    VoidCallback? openSettings,
    GameController Function(int, LevelConfig, AppDependencies)?
    controllerFactory,
    SpeechSource? speech,
    bool? sayItEnabled,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (safetyAcked) 'progress.safetyAck': true,
      if (sayItEnabled ?? false) 'progress.sayIt': true,
      if (sayItEnabled == false) 'progress.sayIt': false,
    });
    store = ProgressStore(await SharedPreferences.getInstance());
    source = FakePoseFrameSource.fromStream(
      const Stream<Never>.empty(),
      outcome: permission,
    );
    final audio = AudioService(
      HarnessTts([]),
      HarnessClips(),
      assetExists: (_) => false,
    );
    captions = [];
    final capSub = audio.captions.listen(captions.add);
    addTearDown(capSub.cancel);
    wakelock = _NoWakelock();
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      GEnglishMotionApp(
        deps: AppDependencies(
          store: store,
          audio: audio,
          repo: repo ?? ContentRepository(content ? [harnessUnit()] : []),
          levels: const [harnessLevel],
          sourceFactory: () => source,
          ticker: () => const Stream<Duration>.empty(),
          wakelock: wakelock,
          openSettings: openSettings,
          controllerFactory: controllerFactory,
          speech: speech,
        ),
      ),
    );
  }

  testWidgets(
    'home renders without any content; Play shows "Chưa có bài học"',
    (tester) async {
      await pumpApp(tester, content: false);
      expect(find.byKey(const ValueKey('play')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('play')));
      await tester.pump();
      expect(find.text('Chưa có bài học'), findsOneWidget);
      expect(tester.takeException(), isNull);
      expect(source.started, isFalse);
      await tester.tap(find.text('Đóng'));
      await tester.pump();
      expect(find.text('Chưa có bài học'), findsNothing);
      expect(find.byKey(const ValueKey('play')), findsOneWidget);
    },
  );

  testWidgets(
    'with the real shipped content Play no longer shows "Chưa có bài học"',
    (tester) async {
      final real = (await tester.runAsync(
        () => ContentRepository.loadFromAssets(rootBundle),
      ))!;
      expect(real.unitsFor(1), isNotEmpty);
      await pumpApp(tester, repo: real);
      await tester.tap(find.byKey(const ValueKey('play')));
      await tester.pump();
      await tester.pump();
      expect(find.text('Chưa có bài học'), findsNothing);
      expect(source.started, isTrue);
    },
  );

  testWidgets('first Play shows the safety screen, then asks for the camera', (
    tester,
  ) async {
    await pumpApp(tester, safetyAcked: false);
    await tester.tap(find.byKey(const ValueKey('play')));
    await tester.pump();
    expect(find.text('Đã hiểu'), findsOneWidget);
    await tester.tap(find.text('Đã hiểu'));
    await tester.pump();
    await tester.pump();
    expect(source.started, isTrue);
    expect(find.textContaining('Giữ yên'), findsOneWidget);
  });

  testWidgets('camera denied shows the permission screen; exit goes home', (
    tester,
  ) async {
    await pumpApp(tester, permission: PermissionOutcome.denied);
    await tester.tap(find.byKey(const ValueKey('play')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Thử lại'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('exit')));
    await tester.pump();
    expect(find.byKey(const ValueKey('play')), findsOneWidget);
  });

  testWidgets('permanently denied: the settings button opens app settings', (
    tester,
  ) async {
    var opened = 0;
    await pumpApp(
      tester,
      permission: PermissionOutcome.permanentlyDenied,
      openSettings: () => opened++,
    );
    await tester.tap(find.byKey(const ValueKey('play')));
    await tester.pump();
    await tester.pump();
    await tester.tap(find.text('Mở Cài đặt'));
    expect(opened, 1);
  });

  test('the default app-settings opener calls permission_handler', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final calls = <String>[];
    const channel = MethodChannel('flutter.baseflow.com/permissions/methods');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      return true;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final d = AppDependencies(
      store: store,
      audio: AudioService(
        HarnessTts([]),
        HarnessClips(),
        assetExists: (_) => false,
      ),
      repo: ContentRepository([]),
      levels: const [],
    );
    d.openSettings();
    await pumpEventQueue();
    expect(calls, ['openAppSettings']);
  });

  testWidgets(
    'the shell clears captions when the controller starts a question',
    (tester) async {
      late GameController made;
      await pumpApp(
        tester,
        controllerFactory: (grade, level, d) => made = GameController(
          grade: grade,
          level: level,
          store: d.store,
          repo: d.repo,
          audio: d.audio,
          ticker: d.ticker,
        ),
      );
      await tester.tap(find.byKey(const ValueKey('play')));
      await tester.pump();
      final shell = tester.widget<GameShell>(find.byType(GameShell));
      expect(shell.captionReset, same(made.captionReset));
      expect(shell.captionFilter, isNotNull);
      await tester.tap(find.byKey(const ValueKey('exit')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    },
  );

  test('default pose source is the plugin adapter, with its camera host', () {
    final audio = AudioService(
      HarnessTts([]),
      HarnessClips(),
      assetExists: (_) => false,
    );
    final d = AppDependencies(
      store: store,
      audio: audio,
      repo: ContentRepository([]),
      levels: const [],
    );
    expect(d.sourceFactory(), isA<PluginPoseFrameSource>());
    expect(d.cameraHost, isA<PoseCameraHost>());

    final injected = AppDependencies(
      store: store,
      audio: audio,
      repo: ContentRepository([]),
      levels: const [],
      sourceFactory: () => FakePoseFrameSource(const []),
    );
    expect(injected.cameraHost, isNull);
  });

  testWidgets('too few distractors: friendly "no lessons", not a dead end', (
    tester,
  ) async {
    await pumpApp(tester, repo: ContentRepository([harnessUnit(count: 2)]));
    final printed = <String>[];
    await captureDebugPrint(printed, () async {
      await tester.tap(find.byKey(const ValueKey('play')));
      await tester.pump();
      await tester.pump();
      await tester.pump();
    });
    expect(
      printed.first,
      startsWith('GameController: planning the level failed'),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('Chưa có bài học'), findsOneWidget);
    expect(source.started, isFalse);
    await tester.tap(find.text('Đóng'));
    await tester.pump();
    expect(find.byKey(const ValueKey('play')), findsOneWidget);
  });

  testWidgets('a start that throws goes home with a friendly message', (
    tester,
  ) async {
    await pumpApp(
      tester,
      controllerFactory: (grade, level, d) => _ThrowingStart(
        grade: grade,
        level: level,
        store: d.store,
        repo: d.repo,
        audio: d.audio,
        ticker: d.ticker,
      ),
    );
    final printed = <String>[];
    await captureDebugPrint(printed, () async {
      await tester.tap(find.byKey(const ValueKey('play')));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump();
    });
    expect(printed.first, startsWith('Starting the game failed: Bad state'));
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('play')), findsOneWidget);
    expect(find.text('Có lỗi rồi, em thử lại sau nhé!'), findsOneWidget);
  });

  testWidgets('the welcome line greets the child once per app session, not '
      'once per level', (tester) async {
    await pumpApp(tester);
    for (var i = 0; i < 2; i++) {
      await tester.tap(find.byKey(const ValueKey('play')));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('exit')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
    }
    expect(captions.where((c) => c == VoiceLine.welcome.caption), hasLength(1));
  });

  testWidgets('camera unavailable shows the unavailable message', (
    tester,
  ) async {
    await pumpApp(tester, permission: PermissionOutcome.unavailable);
    await tester.tap(find.byKey(const ValueKey('play')));
    await tester.pump();
    await tester.pump();
    expect(find.text('Camera chưa sẵn sàng trên máy này'), findsOneWidget);
    expect(find.text('Thử lại'), findsOneWidget);
  });

  testWidgets('the back dialog pauses the game and does not push "Thoát"', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'progress.safetyAck': true});
    store = ProgressStore(await SharedPreferences.getInstance());
    final sources = <_RecSource>[];
    final ticks = StreamController<Duration>.broadcast(sync: true);
    addTearDown(ticks.close);
    late GameController ctl;
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      GEnglishMotionApp(
        deps: AppDependencies(
          store: store,
          audio: AudioService(
            HarnessTts([]),
            HarnessClips(),
            assetExists: (_) => false,
          ),
          repo: ContentRepository([harnessUnit()]),
          levels: const [harnessLevel],
          sourceFactory: () {
            final src = _RecSource(sources.length + 1, []);
            sources.add(src);
            return src;
          },
          ticker: () => ticks.stream,
          wakelock: _NoWakelock(),
          controllerFactory: (grade, level, d) => ctl = GameController(
            grade: grade,
            level: level,
            store: d.store,
            repo: d.repo,
            audio: d.audio,
            ticker: d.ticker,
            welcome: d.welcome,
          ),
        ),
      ),
    );
    await tester.tap(find.byKey(const ValueKey('play')));
    await tester.pump();
    await tester.pump();
    var t = Duration.zero;
    Future<void> step() async {
      t += const Duration(milliseconds: 33);
      sources.last.framesCtl.add(PoseFrame([makePose()], t));
      ticks.add(t);
      await tester.pump(const Duration(milliseconds: 33));
    }

    for (var i = 0; i < 400 && ctl.phase != GamePhase.playing; i++) {
      await step();
    }
    expect(ctl.phase, GamePhase.playing);
    for (var i = 0; i < 20 && ctl.session!.phase != SessionPhase.playing; i++) {
      await step();
    }
    expect(ctl.session!.phase, SessionPhase.playing);

    // A system back while playing: the confirmation must pause the round.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Thoát trò chơi?'), findsOneWidget);

    final left = ctl.session!.round.remaining;
    for (var i = 0; i < 30; i++) {
      await step();
    }
    expect(
      ctl.session!.round.remaining,
      left,
      reason: 'the clock must stand still while the grown-up decides',
    );
    expect(ctl.session!.phase, SessionPhase.paused);

    // The destructive choice is not the emphasised one.
    expect(
      tester.widget(find.byKey(const ValueKey('stay'))),
      isA<FilledButton>(),
      reason: '"Ở lại" is the emphasised button',
    );
    expect(
      tester.widget(find.byKey(const ValueKey('leave'))),
      isNot(isA<FilledButton>()),
      reason: '"Thoát" must not invite a tap',
    );

    // Staying resumes the round.
    await tester.tap(find.byKey(const ValueKey('stay')));
    await tester.pumpAndSettle();
    expect(find.text('Thoát trò chơi?'), findsNothing);
    expect(ctl.session!.phase, SessionPhase.playing);
    for (var i = 0; i < 10; i++) {
      await step();
    }
    expect(ctl.session!.round.remaining, lessThan(left));

    // The in-play exit button takes the same path as the system back: the
    // confirmation appears and the clock stands still.
    await tester.tap(find.byKey(const ValueKey('exit')));
    await tester.pumpAndSettle();
    expect(find.text('Thoát trò chơi?'), findsOneWidget);
    expect(ctl.session!.phase, SessionPhase.paused);
    final frozen = ctl.session!.round.remaining;
    for (var i = 0; i < 30; i++) {
      await step();
    }
    expect(ctl.session!.round.remaining, frozen);
    await tester.tap(find.byKey(const ValueKey('leave')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
  });

  testWidgets('a huge system font setting is clamped: the fixed text boxes '
      'keep their headroom', (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpApp(tester);
    final ctx = tester.element(find.byKey(const ValueKey('play')));
    expect(
      MediaQuery.textScalerOf(ctx).scale(100),
      lessThanOrEqualTo(100 * ClampedTextScale.maxScale),
    );
    expect(tester.takeException(), isNull);
  });

  group('SayIt wiring', () {
    final entry = find.byKey(const ValueKey('sayit-entry'));
    // Words the SayIt generator can pick.
    final sayItRepo = ContentRepository([
      harnessUnit(modes: const [ModeKind.laneJump, ModeKind.sayIt]),
    ]);

    /// Answers the parent gate's multiplication question.
    Future<void> passGate(WidgetTester tester) async {
      final text = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .firstWhere((d) => RegExp(r'^\d+ × \d+ = \?$').hasMatch(d));
      final m = RegExp(r'^(\d+) × (\d+)').firstMatch(text)!;
      final answer = int.parse(m.group(1)!) * int.parse(m.group(2)!);
      for (final d in '$answer'.split('')) {
        await tester.tap(find.byKey(ValueKey('key-$d')));
        await tester.pump();
      }
      await tester.tap(find.byKey(const ValueKey('key-ok')));
      await tester.pumpAndSettle();
    }

    testWidgets('a fresh install: nothing is offered and the OS is never '
        'asked behind the parent\'s back', (tester) async {
      final speech = _FakeSpeech();
      await pumpApp(tester, speech: speech);
      expect(
        store.sayItEnabled,
        isFalse,
        reason: 'what the parent sees switched off is what Home offers',
      );
      expect(entry, findsNothing);
      expect(speech.asked, 0, reason: 'no microphone question on first launch');
    });

    for (final a in [
      SpeechAvailability.noOnDeviceRecognizer,
      SpeechAvailability.noPermission,
    ]) {
      testWidgets('the entry stays hidden for $a', (tester) async {
        final speech = _FakeSpeech(availability: a);
        await pumpApp(tester, speech: speech, sayItEnabled: true);
        expect(entry, findsNothing);
        expect(speech.asked, 0);
      });
    }

    testWidgets('the parent area is the only place that asks for the '
        'microphone, and switching it on reveals the entry', (tester) async {
      final speech = _FakeSpeech();
      await pumpApp(tester, speech: speech, sayItEnabled: false);
      expect(entry, findsNothing);
      expect(speech.asked, 0);
      await tester.tap(find.byKey(const ValueKey('parent-button')));
      await tester.pumpAndSettle();
      await passGate(tester);
      await tester.tap(find.byKey(const ValueKey('toggle-sayit')));
      await tester.pumpAndSettle();
      expect(store.sayItEnabled, isTrue);
      expect(speech.asked, 1, reason: 'asked behind the parent gate, once');
      await tester.tap(find.byTooltip('Quay lại'));
      await tester.pumpAndSettle();
      expect(entry, findsOneWidget);
    });

    testWidgets('leaving SayIt cancels the listening session and drops the '
        'wakelock', (tester) async {
      final speech = _FakeSpeech();
      await pumpApp(
        tester,
        speech: speech,
        sayItEnabled: true,
        repo: sayItRepo,
      );
      // The availability check is async: Home shows the entry once it is in.
      await tester.pump();
      await tester.pump();
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SayItScreen), findsOneWidget);
      expect(find.byType(GameShell), findsNothing, reason: 'no camera');
      expect(find.byType(PoseCameraHost), findsNothing);
      expect(speech.ids, isNotEmpty, reason: 'the microphone is open');
      expect(wakelock.log, contains('enable'));
      await tester.tap(find.byKey(const ValueKey('exit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SayItScreen), findsNothing);
      expect(speech.cancels, greaterThan(0), reason: 'listening is cancelled');
      expect(wakelock.log.last, 'disable');
    });

    testWidgets('back out of SayIt leaves it the same way', (tester) async {
      final speech = _FakeSpeech();
      await pumpApp(
        tester,
        speech: speech,
        sayItEnabled: true,
        repo: sayItRepo,
      );
      await tester.pump();
      await tester.pump();
      await tester.tap(entry);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byType(SayItScreen), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SayItScreen), findsNothing);
      expect(find.byKey(const ValueKey('play')), findsOneWidget);
      expect(speech.cancels, greaterThan(0));
    });
  });

  testWidgets('parent button opens the gate', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const ValueKey('parent-button')));
    await tester.pumpAndSettle();
    expect(find.text('Dành cho bố mẹ'), findsWidgets);
    await tester.tap(find.byTooltip('Quay lại'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('play')), findsOneWidget);
  });

  testWidgets(
    'Play again starts the new camera only after the old one stopped',
    (tester) async {
      SharedPreferences.setMockInitialValues({'progress.safetyAck': true});
      store = ProgressStore(await SharedPreferences.getInstance());
      final log = <String>[];
      final sources = <_RecSource>[];
      final ticks = StreamController<Duration>.broadcast(sync: true);
      addTearDown(ticks.close);
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        GEnglishMotionApp(
          deps: AppDependencies(
            store: store,
            audio: AudioService(
              HarnessTts([]),
              HarnessClips(),
              assetExists: (_) => false,
            ),
            repo: ContentRepository([harnessUnit()]),
            levels: const [
              LevelConfig(
                level: 1,
                questionCount: 1,
                baseTime: Duration(seconds: 1),
                choiceCount: 3,
                hints: HintMode.full,
                window: UnitWindow.current,
              ),
            ],
            sourceFactory: () {
              final src = _RecSource(sources.length + 1, log);
              sources.add(src);
              return src;
            },
            ticker: () => ticks.stream,
            wakelock: _NoWakelock(),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('play')));
      await tester.pump();
      await tester.pump();
      var t = Duration.zero;
      Future<void> step() async {
        t += const Duration(milliseconds: 33);
        sources.last.framesCtl.add(PoseFrame([makePose()], t));
        ticks.add(t);
        await tester.pump(const Duration(milliseconds: 33));
      }

      for (
        var i = 0;
        i < 400 && find.text('Chơi lại').evaluate().isEmpty;
        i++
      ) {
        await step();
      }
      expect(find.text('Chơi lại'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 10));
      // Finished: the camera is already being stopped (slowly).
      expect(log, ['start1', 'stop1:begin']);
      await tester.tap(find.text('Chơi lại'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(log, isNot(contains('start2')), reason: 'old stop still running');
      await tester.pump(const Duration(milliseconds: 500));
      expect(log, ['start1', 'stop1:begin', 'stop1:end', 'start2']);
      // Leave: the second camera is stopped too.
      await tester.tap(find.byKey(const ValueKey('exit')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(log.last, 'stop2:end');
      expect(sources.map((x) => x.stops), [1, 1]);
    },
  );

  testWidgets(
    'a camera that never delivers frames shows the camera-problem screen; '
    'Thử lại releases the old source before the new one starts',
    (tester) async {
      SharedPreferences.setMockInitialValues({'progress.safetyAck': true});
      store = ProgressStore(await SharedPreferences.getInstance());
      final log = <String>[];
      final sources = <_RecSource>[];
      final ticks = StreamController<Duration>.broadcast(sync: true);
      addTearDown(ticks.close);
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        GEnglishMotionApp(
          deps: AppDependencies(
            store: store,
            audio: AudioService(
              HarnessTts([]),
              HarnessClips(),
              assetExists: (_) => false,
            ),
            repo: ContentRepository([harnessUnit()]),
            levels: const [harnessLevel],
            sourceFactory: () {
              final src = _RecSource(sources.length + 1, log);
              sources.add(src);
              return src;
            },
            ticker: () => ticks.stream,
            wakelock: _NoWakelock(),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('play')));
      await tester.pump();
      await tester.pump();
      var t = Duration.zero;
      for (var i = 0; i < 200; i++) {
        t += const Duration(milliseconds: 33);
        ticks.add(t);
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(find.text('Camera không hoạt động'), findsOneWidget);
      expect(
        find.text('Kiểm tra quyền camera và khởi động lại ứng dụng'),
        findsOneWidget,
      );
      expect(find.text('Về trang chính'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 300));
      expect(log, ['start1', 'stop1:begin', 'stop1:end']);

      await tester.tap(find.text('Thử lại'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(log, ['start1', 'stop1:begin', 'stop1:end', 'start2']);
      expect(find.text('Camera không hoạt động'), findsNothing);

      // Home from a second failure.
      for (var i = 0; i < 200; i++) {
        t += const Duration(milliseconds: 33);
        ticks.add(t);
        await tester.pump(const Duration(milliseconds: 33));
      }
      expect(find.text('Camera không hoạt động'), findsOneWidget);
      await tester.tap(find.text('Về trang chính'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byKey(const ValueKey('play')), findsOneWidget);
    },
  );

  testWidgets('app lifecycle changes reach the running controller', (
    tester,
  ) async {
    late GameController made;
    await pumpApp(
      tester,
      controllerFactory: (grade, level, d) => made = GameController(
        grade: grade,
        level: level,
        store: d.store,
        repo: d.repo,
        audio: d.audio,
        ticker: d.ticker,
      ),
    );
    await tester.tap(find.byKey(const ValueKey('play')));
    await tester.pump();
    await tester.pump();
    expect(made.appActive, isTrue);
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    expect(made.appActive, isFalse);
    binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(made.appActive, isTrue);
  });

  Future<void> leave(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('exit')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<(List<String>, List<_RecSource>)> pumpFlow(
    WidgetTester tester, {
    Completer<void>? firstGate,
    String? closedMode,
    Duration closeTimeout = const Duration(seconds: 3),
  }) async {
    SharedPreferences.setMockInitialValues({'progress.safetyAck': true});
    store = ProgressStore(await SharedPreferences.getInstance());
    final log = <String>[];
    final sources = <_RecSource>[];
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final audio = AudioService(
      HarnessTts([]),
      HarnessClips(),
      assetExists: (_) => false,
    );
    await tester.pumpWidget(
      GEnglishMotionApp(
        deps: AppDependencies(
          store: store,
          audio: audio,
          repo: ContentRepository([harnessUnit()]),
          levels: const [harnessLevel],
          sourceFactory: () {
            final src = _RecSource(
              sources.length + 1,
              log,
              gate: sources.isEmpty ? firstGate : null,
            );
            sources.add(src);
            return src;
          },
          ticker: () => const Stream<Duration>.empty(),
          wakelock: _NoWakelock(),
          closeTimeout: closeTimeout,
          controllerFactory: closedMode == null
              ? null
              : (grade, level, d) => _HangingClosed(
                  grade: grade,
                  level: level,
                  store: d.store,
                  repo: d.repo,
                  audio: d.audio,
                  ticker: d.ticker,
                  mode: closedMode,
                ),
        ),
      ),
    );
    return (log, sources);
  }

  testWidgets('system back in a play flow closes it through the controller', (
    tester,
  ) async {
    final (log, sources) = await pumpFlow(tester);
    await tester.tap(find.byKey(const ValueKey('play')));
    await tester.pump();
    await tester.pump();
    var t = Duration.zero;
    for (
      var i = 0;
      i < 80 && find.byKey(const ValueKey('lane-0')).evaluate().isEmpty;
      i++
    ) {
      t += const Duration(milliseconds: 33);
      sources.last.framesCtl.add(PoseFrame([makePose()], t));
      await tester.pump(const Duration(milliseconds: 33));
    }
    expect(find.byKey(const ValueKey('lane-0')), findsOneWidget);

    // Back asks first; staying keeps playing and the camera running.
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.text('Thoát trò chơi?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('stay')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byKey(const ValueKey('lane-0')), findsOneWidget);
    expect(sources.last.stops, 0);

    // Leaving goes Home and releases the camera (controller close path).
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('leave')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('play')), findsOneWidget);
    expect(sources.last.stops, 1);
    expect(log.last, startsWith('stop1'));
  });

  testWidgets('system back before the game runs goes straight home', (
    tester,
  ) async {
    final (_, sources) = await pumpFlow(tester);
    await tester.tap(find.byKey(const ValueKey('play')));
    await tester.pump();
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const ValueKey('play')), findsOneWidget);
    expect(sources.last.stops, 1);
  });

  testWidgets(
    'dispose during a pending permission start: next camera waits for the orphan stop',
    (tester) async {
      final gate = Completer<void>();
      final (log, sources) = await pumpFlow(tester, firstGate: gate);
      await tester.tap(find.byKey(const ValueKey('play')));
      await tester.pump();
      await tester.pump();
      expect(log, ['start1']);
      await tester.tap(find.byKey(const ValueKey('exit')));
      await tester.pump();
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('play')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(log, ['start1'], reason: 'old start still pending');
      gate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(log, ['start1', 'stop1:begin', 'stop1:end', 'start2']);
      expect(sources.map((x) => x.stops), [1, 0]);
      await leave(tester);
    },
  );

  for (final mode in ['hang', 'throw']) {
    testWidgets('closed that ${mode}s does not block the next game', (
      tester,
    ) async {
      final printed = <String>[];
      final (log, _) = await pumpFlow(
        tester,
        closedMode: mode,
        closeTimeout: const Duration(milliseconds: 300),
      );
      await captureDebugPrint(printed, () async {
        await tester.tap(find.byKey(const ValueKey('play')));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('exit')));
        await tester.pump();
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('play')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        if (mode == 'hang') {
          expect(
            log,
            isNot(contains('start2')),
            reason: 'waits for the timeout',
          );
        }
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump();
        expect(log.where((e) => e == 'start2'), hasLength(1));
        await leave(tester);
        await tester.pump(const Duration(seconds: 1));
      });
      if (mode == 'hang') {
        expect(printed, contains('close timed out — possible camera overlap'));
      } else {
        expect(
          printed.where(
            (m) => m.startsWith('Closing the previous game failed'),
          ),
          isNotEmpty,
        );
      }
    });
  }
}

class _HangingClosed extends GameController {
  _HangingClosed({
    required super.grade,
    required super.level,
    required super.store,
    required super.repo,
    required super.audio,
    required super.ticker,
    required this.mode,
  });
  final String mode;
  @override
  Future<void> get closed => mode == 'hang'
      ? Completer<void>().future
      : Future<void>.error(StateError('boom'));
}

class _RecSource implements PoseFrameSource {
  _RecSource(this.n, this.log, {this.gate});
  final Completer<void>? gate;
  final int n;
  final List<String> log;
  final frames0 = StreamController<PoseFrame>(sync: true);
  int stops = 0;

  @override
  Stream<PoseFrame> get frames => frames0.stream;

  StreamController<PoseFrame> get framesCtl => frames0;

  @override
  Stream<PoseSourceFailure> get failures => const Stream.empty();

  @override
  Future<PermissionOutcome> start() async {
    log.add('start$n');
    await gate?.future;
    return PermissionOutcome.granted;
  }

  @override
  Future<void> stop() async {
    stops++;
    log.add('stop$n:begin');
    await Future<void>.delayed(const Duration(milliseconds: 200));
    log.add('stop$n:end');
  }
}
