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
import 'package:g_english_motion/ui/shell/break_reminder.dart';
import 'package:g_english_motion/ui/shell/calibration_screen.dart';
import 'package:g_english_motion/ui/shell/caption_strip.dart';
import 'package:g_english_motion/ui/shell/game_shell.dart';
import 'package:g_english_motion/ui/shell/pause_overlay.dart';
import 'package:g_english_motion/ui/shell/permission_screen.dart';
import 'package:g_english_motion/ui/shell/play_surface.dart';
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

    testWidgets('unavailable shows its own message and retry only', (
      tester,
    ) async {
      var retry = 0, settings = 0;
      await tester.pumpWidget(
        _app(
          PermissionScreen(
            outcome: PermissionOutcome.unavailable,
            onRetry: () => retry++,
            onOpenSettings: () => settings++,
          ),
        ),
      );
      expect(find.text('Camera chưa sẵn sàng trên máy này'), findsOneWidget);
      expect(find.text('Mở Cài đặt'), findsNothing);
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
      ProgressStore? store,
    }) => _app(
      GameShell(
        session: sess ?? session,
        events: ev ?? events.stream,
        elapsed: () => clock,
        audio: audio,
        wakelock: wl ?? wakelock,
        store: store,
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

    /// Fires the armed break timer and lets the audio future run.
    Future<void> fireBreak(WidgetTester tester) async {
      final t = timers.lastWhere((x) => x.isActive);
      await tester.runAsync(() async {
        t.fire();
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });
      await tester.pump();
    }

    testWidgets('shows what the voice says in a caption strip', (tester) async {
      await tester.pumpWidget(
        _app(
          GameShell(
            session: session,
            events: events.stream,
            elapsed: () => clock,
            audio: audio,
            wakelock: wakelock,
            captionFilter: (c) => c != 'ball',
            child: const Text('PLAYFIELD'),
          ),
        ),
      );
      // AudioService chains real futures: let them run on the real clock.
      await tester.runAsync(() async {
        await audio.playLine(VoiceLine.welcome);
        await audio.sayEnglish('ball');
      });
      await tester.pump();
      expect(captions, [VoiceLine.welcome.caption, 'ball']);
      expect(find.text(VoiceLine.welcome.caption), findsOneWidget);
      // The filtered English word neither shows nor replaces the line.
      expect(find.text('ball'), findsNothing);
      // Dispose (cancels the strip's hide timer).
      await tester.pumpWidget(const SizedBox());
    });

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

    testWidgets('the pause overlay never covers the caption strip', (
      tester,
    ) async {
      await tester.pumpWidget(shell());
      events.add(const PlayerLost(at: Duration.zero));
      await _settle(tester);
      expect(find.byType(PauseOverlay), findsOneWidget);
      final overlay = tester.getRect(find.byType(PauseOverlay));
      final strip = tester.getRect(find.byType(CaptionStrip));
      expect(
        overlay.overlaps(strip),
        isFalse,
        reason: 'a line spoken as the child steps out must stay readable',
      );
      // And a caption that arrives while paused is shown.
      await tester.runAsync(() async {
        await audio.playLine(VoiceLine.standStill);
      });
      await tester.pump();
      expect(find.text(VoiceLine.standStill.caption), findsOneWidget);
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

    testWidgets('the break reminder is visible, pauses the game, is dismissed '
        'by a grown-up and comes back after every breakAfter', (tester) async {
      await tester.pumpWidget(shell());
      expect(timers, hasLength(1));
      expect(timers.single.duration, const Duration(minutes: 20));
      await fireBreak(tester);
      // Spoken AND shown: the reminder is not audio-only any more.
      expect(captions, [VoiceLine.takeABreak.caption]);
      expect(find.byType(BreakReminder), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BreakReminder),
          matching: find.text(BreakReminder.message),
        ),
        findsOneWidget,
      );
      expect(session.log, ['pause'], reason: 'the game waits');
      // The caption strip is still readable under it.
      expect(
        tester
            .getRect(find.byType(BreakReminder))
            .overlaps(tester.getRect(find.byType(CaptionStrip))),
        isFalse,
      );
      // A grown-up dismisses it; the game resumes and the clock restarts.
      await tester.tap(find.byKey(const ValueKey('break-dismiss')));
      await tester.pump();
      expect(find.byType(BreakReminder), findsNothing);
      expect(session.log, ['pause', 'resume']);
      final armed = timers.lastWhere((t) => t.isActive);
      expect(armed.duration, const Duration(minutes: 20));
      // ... and it reminds again after the next 20 minutes.
      await fireBreak(tester);
      expect(captions, hasLength(2));
      expect(find.byType(BreakReminder), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('play time is banked in the store, so going Home between two '
        'short levels does not restart the 20 minutes', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = ProgressStore(await SharedPreferences.getInstance());
      await tester.pumpWidget(shell(store: store));
      clock += const Duration(minutes: 8);
      // Leaving the play flow (a new shell per flow) banks what was played.
      await tester.pumpWidget(const SizedBox());
      expect(store.playedTowardsBreak(), const Duration(minutes: 8));
      // The next flow continues the same 20 minutes.
      clock = Duration.zero;
      timers.clear();
      await tester.pumpWidget(shell(store: store));
      expect(timers.single.duration, const Duration(minutes: 12));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('backgrounding stops the break clock after a frame and does '
        'not bank idle time', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = ProgressStore(await SharedPreferences.getInstance());
      await tester.pumpWidget(shell(store: store));
      final armed = timers.single;
      clock += const Duration(minutes: 18);
      life(AppLifecycleState.paused);
      await tester.pump();
      expect(armed.cancelled, isTrue, reason: 'no reminder to an empty screen');
      // The phone sits locked for 10 minutes.
      clock += const Duration(minutes: 10);
      await tester.pump();
      expect(store.playedTowardsBreak(), const Duration(minutes: 18));
      // Coming back re-arms with the 2 minutes that are left.
      life(AppLifecycleState.resumed);
      await tester.pump();
      expect(timers.last.isActive, isTrue);
      expect(timers.last.duration, const Duration(minutes: 2));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('PlaySurface re-arms by itself when the host sets no '
        'callbacks', (tester) async {
      await tester.pumpWidget(
        _app(
          PlaySurface(
            audio: audio,
            elapsed: () => clock,
            timerFactory: (d, cb) {
              final t = _FakeTimer(d, cb);
              timers.add(t);
              return t;
            },
            child: const Text('PLAYFIELD'),
          ),
        ),
      );
      expect(timers.single.duration, const Duration(minutes: 20));
      clock += const Duration(minutes: 20);
      await fireBreak(tester);
      expect(captions, [VoiceLine.takeABreak.caption]);
      final next = timers.lastWhere((t) => t.isActive);
      expect(next, isNot(same(timers.first)));
      expect(next.duration, const Duration(minutes: 20));
      clock += const Duration(minutes: 20);
      await fireBreak(tester);
      expect(captions, hasLength(2), reason: 'a second reminder is due');
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a reminder clears the banked play time', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final store = ProgressStore(await SharedPreferences.getInstance());
      await store.addPlayTime(const Duration(minutes: 5));
      await tester.pumpWidget(shell(store: store));
      expect(timers.single.duration, const Duration(minutes: 15));
      await fireBreak(tester);
      expect(store.playedTowardsBreak(), Duration.zero);
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
