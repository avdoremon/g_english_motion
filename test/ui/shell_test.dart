import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/audio/audio_service.dart';
import 'package:g_english_motion/audio/voice_lines.dart';
import 'package:g_english_motion/input/calibrator.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/input/pose_frame_source.dart';
import 'package:g_english_motion/progress/progress_store.dart';
import 'package:g_english_motion/ui/shell/banner_slot.dart';
import 'package:g_english_motion/ui/shell/calibration_screen.dart';
import 'package:g_english_motion/ui/shell/game_shell.dart';
import 'package:g_english_motion/ui/shell/pause_overlay.dart';
import 'package:g_english_motion/ui/shell/permission_screen.dart';
import 'package:g_english_motion/ui/shell/safety_screen.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Tts implements SpeechEngine {
  @override
  Future<bool> isEnglishAvailable() async => false;
  @override
  Future<void> speak(String text) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _Clips implements ClipPlayer {
  @override
  Future<bool> play(String assetPath) async => false;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

class _FakeSession implements PausableSession {
  final log = <String>[];
  @override
  void pause() => log.add('pause');
  @override
  void resume() => log.add('resume');
}

class _FakeWakelock implements Wakelock {
  final log = <String>[];
  @override
  Future<void> enable() async => log.add('enable');
  @override
  Future<void> disable() async => log.add('disable');
}

class _ThrowingWakelock implements Wakelock {
  @override
  Future<void> enable() async => throw StateError('no wakelock');
  @override
  Future<void> disable() async {}
}

class _FakeTimer implements Timer {
  _FakeTimer(this.duration, this.cb);
  final Duration duration;
  final void Function() cb;
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
  void fire() => cb();
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => 0;
}

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(body: child),
);

/// Lets stream/microtask deliveries and the following frame happen.
Future<void> _settle(WidgetTester t) async {
  await t.pump(const Duration(milliseconds: 10));
  await t.pump(const Duration(milliseconds: 10));
}

void main() {
  group('SafetyScreen', () {
    late ProgressStore store;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = ProgressStore(await SharedPreferences.getInstance());
    });

    testWidgets('needed until acknowledged; button acknowledges', (
      tester,
    ) async {
      expect(SafetyScreen.needed(store), isTrue);
      var done = 0;
      await tester.pumpWidget(
        _app(SafetyScreen(store: store, onAcknowledged: () => done++)),
      );
      expect(find.textContaining('TV'), findsWidgets);
      await tester.tap(find.text('Đã hiểu'));
      await tester.pump();
      expect(SafetyScreen.needed(store), isFalse);
      expect(done, 1);
    });

    testWidgets('button is at least 56 dp tall', (tester) async {
      await tester.pumpWidget(
        _app(SafetyScreen(store: store, onAcknowledged: () {})),
      );
      final size = tester.getSize(find.byType(FilledButton));
      expect(size.height, greaterThanOrEqualTo(56));
    });
  });

  group('PermissionScreen', () {
    testWidgets('denied shows retry only', (tester) async {
      var retry = 0, settings = 0;
      await tester.pumpWidget(
        _app(
          PermissionScreen(
            outcome: PermissionOutcome.denied,
            onRetry: () => retry++,
            onOpenSettings: () => settings++,
          ),
        ),
      );
      expect(find.text('Mở Cài đặt'), findsNothing);
      expect(find.textContaining('camera'), findsWidgets);
      await tester.tap(find.text('Thử lại'));
      expect(retry, 1);
      expect(settings, 0);
    });

    testWidgets('permanentlyDenied shows open settings', (tester) async {
      var settings = 0;
      await tester.pumpWidget(
        _app(
          PermissionScreen(
            outcome: PermissionOutcome.permanentlyDenied,
            onRetry: () {},
            onOpenSettings: () => settings++,
          ),
        ),
      );
      await tester.tap(find.text('Mở Cài đặt'));
      expect(settings, 1);
    });
  });

  group('CalibrationScreen', () {
    const cases = {
      CalibrationIssue.tooClose: 'Lùi ra xa hơn một chút',
      CalibrationIssue.notStill: 'Đứng yên một chút nhé',
      CalibrationIssue.notCentered: 'Đứng vào giữa màn hình',
      CalibrationIssue.noPerson: 'Em chưa vào khung hình',
    };
    cases.forEach((issue, text) {
      testWidgets('shows "$text" for $issue', (tester) async {
        await tester.pumpWidget(
          _app(
            CalibrationScreen(
              progress: CalibrationProgress(progress: 0.3, issue: issue),
            ),
          ),
        );
        expect(find.text(text), findsOneWidget);
        final style = tester.widget<Text>(find.text(text)).style!;
        expect(style.fontSize, greaterThanOrEqualTo(28));
      });
    });

    testWidgets('no issue shows hold-still text and progress ring', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          const CalibrationScreen(progress: CalibrationProgress(progress: 0.5)),
        ),
      );
      expect(find.text('Giữ yên nhé…'), findsOneWidget);
      expect(
        find.bySemanticsLabel('Đang căn chỉnh, 50 phần trăm'),
        findsOneWidget,
      );
      final ind = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(ind.value, 0.5);
    });
  });

  testWidgets('PauseOverlay shows large message', (tester) async {
    await tester.pumpWidget(
      _app(const PauseOverlay(message: 'Em đâu rồi? Quay lại khung hình nhé')),
    );
    final t = tester.widget<Text>(
      find.text('Em đâu rồi? Quay lại khung hình nhé'),
    );
    expect(t.style!.fontSize, greaterThanOrEqualTo(28));
  });

  testWidgets('BannerSlot is empty for now', (tester) async {
    await tester.pumpWidget(_app(const BannerSlot()));
    expect(tester.getSize(find.byType(BannerSlot)), Size.zero);
  });

  group('GameShell', () {
    late _FakeSession session;
    late _FakeWakelock wakelock;
    late StreamController<GameInputEvent> events;
    late AudioService audio;
    late List<String> captions;
    late List<_FakeTimer> timers;
    late StreamSubscription<String> capSub;
    var clock = Duration.zero;
    final binding = TestWidgetsFlutterBinding.ensureInitialized();

    setUp(() {
      session = _FakeSession();
      wakelock = _FakeWakelock();
      events = StreamController<GameInputEvent>.broadcast();
      audio = AudioService(_Tts(), _Clips(), assetExists: (_) => false);
      captions = [];
      capSub = audio.captions.listen(captions.add);
      timers = [];
      clock = Duration.zero;
    });

    tearDown(() async {
      await capSub.cancel();
      await audio.dispose();
      await events.close();
    });

    Widget shell({
      bool showBanner = false,
      PausableSession? sess,
      Stream<GameInputEvent>? ev,
      Wakelock? wl,
    }) => _app(
      GameShell(
        session: sess ?? session,
        events: ev ?? events.stream,
        elapsed: () => clock,
        audio: audio,
        wakelock: wl ?? wakelock,
        breakAfter: const Duration(minutes: 20),
        timerFactory: (d, cb) {
          final t = _FakeTimer(d, cb);
          timers.add(t);
          return t;
        },
        showBanner: showBanner,
        child: const Text('PLAYFIELD'),
      ),
    );

    testWidgets('wakelock on init, off on dispose', (tester) async {
      await tester.pumpWidget(shell());
      expect(find.text('PLAYFIELD'), findsOneWidget);
      expect(wakelock.log, ['enable']);
      await tester.pumpWidget(const SizedBox());
      expect(wakelock.log, ['enable', 'disable']);
    });

    void life(AppLifecycleState st) =>
        binding.handleAppLifecycleStateChanged(st);

    testWidgets('inactive alone pauses; resumed with player present resumes', (
      tester,
    ) async {
      await tester.pumpWidget(shell());
      life(AppLifecycleState.inactive);
      expect(session.log, ['pause']);
      life(AppLifecycleState.paused);
      expect(session.log, ['pause']);
      life(AppLifecycleState.resumed);
      expect(session.log, ['pause', 'resume']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Lost -> inactive -> resumed does not resume', (tester) async {
      await tester.pumpWidget(shell());
      events.add(const PlayerLost(at: Duration.zero));
      await _settle(tester);
      life(AppLifecycleState.inactive);
      life(AppLifecycleState.resumed);
      expect(session.log, ['pause']);
      events.add(const PlayerFound(at: Duration(seconds: 1)));
      await _settle(tester);
      expect(session.log, ['pause', 'resume']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Lost -> Found while app inactive does not resume', (
      tester,
    ) async {
      await tester.pumpWidget(shell());
      events.add(const PlayerLost(at: Duration.zero));
      await _settle(tester);
      life(AppLifecycleState.inactive);
      events.add(const PlayerFound(at: Duration(seconds: 1)));
      await _settle(tester);
      expect(session.log, ['pause']);
      expect(find.byType(PauseOverlay), findsNothing);
      life(AppLifecycleState.resumed);
      expect(session.log, ['pause', 'resume']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('dispose: unsubscribes and ignores lifecycle', (tester) async {
      await tester.pumpWidget(shell());
      expect(events.hasListener, isTrue);
      await tester.pumpWidget(const SizedBox());
      expect(events.hasListener, isFalse);
      life(AppLifecycleState.inactive);
      expect(session.log, isEmpty);
    });

    testWidgets('wakelock enable failure is swallowed', (tester) async {
      await tester.pumpWidget(shell(wl: _ThrowingWakelock()));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('swapped events stream resubscribes', (tester) async {
      final other = StreamController<GameInputEvent>.broadcast();
      addTearDown(other.close);
      await tester.pumpWidget(shell());
      await tester.pumpWidget(shell(ev: other.stream));
      expect(events.hasListener, isFalse);
      expect(other.hasListener, isTrue);
      other.add(const PlayerLost(at: Duration.zero));
      await _settle(tester);
      expect(session.log, ['pause']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('swapping events while lost resyncs to player present', (
      tester,
    ) async {
      final other = StreamController<GameInputEvent>.broadcast();
      addTearDown(other.close);
      await tester.pumpWidget(shell());
      events.add(const PlayerLost(at: Duration.zero));
      await _settle(tester);
      expect(find.byType(PauseOverlay), findsOneWidget);
      await tester.pumpWidget(shell(ev: other.stream));
      await _settle(tester);
      expect(find.byType(PauseOverlay), findsNothing);
      expect(session.log, ['pause', 'resume']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('swapped session is paused only when not running', (
      tester,
    ) async {
      final next = _FakeSession();
      await tester.pumpWidget(shell());
      await tester.pumpWidget(shell(sess: next));
      expect(next.log, isEmpty);
      events.add(const PlayerLost(at: Duration.zero));
      await _settle(tester);
      final third = _FakeSession();
      await tester.pumpWidget(shell(sess: third));
      expect(third.log, ['pause']);
      expect(next.log, ['pause']);
      events.add(const PlayerFound(at: Duration(seconds: 1)));
      await _settle(tester);
      expect(third.log, ['pause', 'resume']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('break clock counts play time only', (tester) async {
      await tester.pumpWidget(shell());
      expect(timers, hasLength(1));
      clock += const Duration(minutes: 5);
      events.add(const PlayerLost(at: Duration.zero));
      await _settle(tester);
      expect(timers[0].cancelled, isTrue);
      clock += const Duration(minutes: 30);
      events.add(const PlayerFound(at: Duration(seconds: 1)));
      await _settle(tester);
      expect(timers, hasLength(2));
      expect(timers[1].duration, const Duration(minutes: 15));
      await tester.pumpWidget(const SizedBox());
      expect(timers[1].cancelled, isTrue);
    });

    testWidgets('PlayerLost shows overlay and pauses; PlayerFound reverses', (
      tester,
    ) async {
      await tester.pumpWidget(shell());
      expect(find.byType(PauseOverlay), findsNothing);
      events.add(const PlayerLost(at: Duration.zero));
      await _settle(tester);
      expect(find.byType(PauseOverlay), findsOneWidget);
      expect(session.log, ['pause']);
      events.add(const PlayerFound(at: Duration(seconds: 1)));
      await _settle(tester);
      expect(find.byType(PauseOverlay), findsNothing);
      expect(session.log, ['pause', 'resume']);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('other events are ignored', (tester) async {
      await tester.pumpWidget(shell());
      events.add(const LaneChanged(1, at: Duration.zero));
      await _settle(tester);
      expect(session.log, isEmpty);
      expect(find.byType(PauseOverlay), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('break reminder plays exactly once after breakAfter', (
      tester,
    ) async {
      await tester.pumpWidget(shell());
      expect(timers, hasLength(1));
      expect(timers.single.duration, const Duration(minutes: 20));
      // AudioService chains real futures: let them run on the real clock.
      await tester.runAsync(() async {
        timers.single.fire();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      expect(captions, [VoiceLine.takeABreak.caption]);
      await tester.runAsync(() async {
        timers.single.fire();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      expect(captions, hasLength(1));
      expect(timers, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('banner slot only when showBanner', (tester) async {
      await tester.pumpWidget(shell());
      expect(find.byType(BannerSlot), findsNothing);
      await tester.pumpWidget(shell(showBanner: true));
      expect(find.byType(BannerSlot), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
