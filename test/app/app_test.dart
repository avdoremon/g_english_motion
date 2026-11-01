import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/app/app.dart';
import 'package:g_english_motion/app/game_controller.dart';
import 'package:g_english_motion/audio/audio_service.dart';
import 'package:g_english_motion/content/content_repository.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/input/pose_frame_source.dart';
import 'package:g_english_motion/input/pose_types.dart';
import 'package:g_english_motion/levels/level_config.dart';
import 'package:g_english_motion/progress/progress_store.dart';
import 'package:g_english_motion/ui/shell/game_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/game_harness.dart';
import '../helpers/synthetic_poses.dart';

class _NoWakelock implements Wakelock {
  @override
  Future<void> enable() async {}
  @override
  Future<void> disable() async {}
}

void main() {
  late ProgressStore store;
  late FakePoseFrameSource source;

  Future<void> pumpApp(
    WidgetTester tester, {
    bool content = true,
    bool safetyAcked = true,
    PermissionOutcome permission = PermissionOutcome.granted,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (safetyAcked) 'progress.safetyAck': true,
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
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      GEnglishMotionApp(
        deps: AppDependencies(
          store: store,
          audio: audio,
          repo: ContentRepository(content ? [harnessUnit()] : []),
          levels: const [harnessLevel],
          sourceFactory: () => source,
          ticker: () => const Stream<Duration>.empty(),
          wakelock: _NoWakelock(),
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

  Future<void> leave(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey('exit')));
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
  }

  Future<(List<String>, List<_RecSource>, Stream<Duration>)> pumpFlow(
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
    return (log, sources, const Stream<Duration>.empty());
  }

  testWidgets(
    'dispose during a pending permission start: next camera waits for the orphan stop',
    (tester) async {
      final gate = Completer<void>();
      final (log, sources, _) = await pumpFlow(tester, firstGate: gate);
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
      final (log, _, _) = await pumpFlow(
        tester,
        closedMode: mode,
        closeTimeout: const Duration(milliseconds: 300),
      );
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
        expect(log, isNot(contains('start2')), reason: 'waits for the timeout');
      }
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(log.where((e) => e == 'start2'), hasLength(1));
      await leave(tester);
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
