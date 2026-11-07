import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/input/pose_types.dart';
import 'package:g_english_motion/levels/level_config.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/modes/sky_shoot.dart';
import 'package:g_english_motion/session/level_session.dart';
import 'package:g_english_motion/ui/mascot/tin_tin.dart';
import 'package:g_english_motion/ui/screens/play_screen.dart';
import 'package:g_english_motion/ui/screens/sky_shoot_screen.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';

import '../helpers/game_harness.dart';

const _four = LevelConfig(
  level: 4,
  questionCount: 8,
  baseTime: Duration(seconds: 12),
  choiceCount: 4,
  hints: HintMode.none,
  window: UnitWindow.current,
);

void main() {
  late GameHarness h;

  Future<void> boot(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
    LevelConfig level = harnessLevel,
    bool useScreen = true,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      h = await GameHarness.create(
        grade: 3,
        modes: const [ModeKind.skyShoot],
        level: level,
      );
      await h.startAndCalibrate();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: useScreen
              ? SkyShootScreen(controller: h.controller)
              : PlayScreen(controller: h.controller),
        ),
      ),
    );
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(h.dispose);
  }

  LevelSession session() => h.controller.session!;
  SkyShootRound round() => session().round as SkyShootRound;
  ChoiceQuestion question() => session().current.question as ChoiceQuestion;

  /// An event time at which a shot lands on answer [index] (or, with null,
  /// on nothing), searching forward on the field's own clock.
  Duration shotAt({int? index}) {
    final r = round();
    final start = h.controller.frameClock;
    for (var ms = 0; ms < 120000; ms += 10) {
      final t = start + Duration(milliseconds: ms);
      final x = r.field.arrowX(t);
      final dists = [
        for (var i = 0; i < question().choices.length; i++)
          (r.field.answerX(i, t) - x).abs(),
      ];
      final ok = index == null
          ? dists.every((d) => d > r.hitRadius + 0.03)
          : dists[index] < r.hitRadius - 0.03;
      if (ok) return t + r.castLatency;
    }
    fail('no such shot time found');
  }

  void shoot({int? at}) {
    h.controller.touchInput(Confirmed(0, at: shotAt(index: at)));
  }

  Future<void> reelIn(WidgetTester tester) async {
    for (final hand in [Hand.left, Hand.right, Hand.left, Hand.right]) {
      h.controller.touchInput(Pulled(hand, at: Duration.zero));
      await tester.pump();
    }
  }

  testWidgets('shows the shots left and the pulls, and updates them', (
    tester,
  ) async {
    await boot(tester);
    expect(session().phase, SessionPhase.playing);
    expect(find.text('Lượt bắn: 3'), findsOneWidget);
    expect(find.text('Kéo dây: 0/4'), findsOneWidget);
    expect(find.byKey(const ValueKey('miss-note')), findsNothing);

    shoot(); // a miss
    await tester.pump();
    expect(find.text('Lượt bắn: 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('miss-note')), findsOneWidget);

    shoot(at: 0);
    await tester.pump();
    expect(round().phase, SkyPhase.reeling);
    expect(find.text('Lượt bắn: 2'), findsOneWidget);
    h.controller.touchInput(Pulled(Hand.left, at: Duration.zero));
    h.controller.touchInput(Pulled(Hand.right, at: Duration.zero));
    await tester.pump();
    expect(find.text('Kéo dây: 2/4'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the right answer reeled in -> Đúng and the celebration', (
    tester,
  ) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('celebration')), findsNothing);
    shoot(at: question().correctIndex);
    await tester.pump();
    await reelIn(tester);
    expect(session().phase, SessionPhase.feedback);
    expect(session().lastResult, RoundResult.correct);
    expect(find.text('Đúng'), findsOneWidget);
    expect(find.byKey(const ValueKey('celebration')), findsOneWidget);
    final dancer = tester.widget<TinTin>(
      find.descendant(
        of: find.byKey(const ValueKey('celebration')),
        matching: find.byType(TinTin),
      ),
    );
    expect(dancer.state, TinTinState.dance);
    await finish(tester);
  });

  testWidgets('a wrong answer reeled in -> Sai, no celebration, the right '
      'answer is marked afterwards', (tester) async {
    await boot(tester);
    final wrong = (question().correctIndex + 1) % question().choices.length;
    shoot(at: wrong);
    await tester.pump();
    await reelIn(tester);
    expect(session().lastResult, RoundResult.wrong);
    expect(find.text('Sai'), findsOneWidget);
    expect(find.byKey(const ValueKey('celebration')), findsNothing);
    expect(
      find.descendant(
        of: find.byKey(ValueKey('answer-${question().correctIndex}')),
        matching: find.byIcon(Icons.check_circle),
      ),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('a timeout shows a neutral Hết giờ, not Sai, and scores as not '
      'correct', (tester) async {
    await boot(tester);
    await tester.runAsync(
      () => h.run(
        const Duration(seconds: 120),
        stopWhen: () => session().phase == SessionPhase.feedback,
      ),
    );
    await tester.pump();
    expect(session().lastResult, RoundResult.timeout);
    expect(find.text('Hết giờ'), findsOneWidget);
    expect(find.text('Sai'), findsNothing);
    expect(find.text('Đúng'), findsNothing);
    expect(find.byIcon(Icons.cancel), findsNothing);
    expect(find.byIcon(Icons.hourglass_bottom), findsOneWidget);
    await finish(tester);
  });

  testWidgets('three misses end the question as wrong', (tester) async {
    await boot(tester);
    for (var i = 0; i < 3; i++) {
      shoot();
      await tester.pump();
    }
    expect(session().lastResult, RoundResult.wrong);
    expect(find.text('Lượt bắn: 0'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('nothing marks the right answer before the child answered', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await boot(tester);
    expect(find.byIcon(Icons.check_circle), findsNothing);
    final label = tester.getSemantics(find.byKey(const ValueKey('sky'))).label;
    final lines = label.split('\n');
    for (final c in question().choices) {
      final word = h.controller.itemFor(c.itemId).word;
      expect(
        lines.where((l) => l == word),
        hasLength(1),
        reason: 'each card is announced as its own word, nothing more',
      );
    }
    expect(label.toLowerCase().contains('đúng'), isFalse);
    handle.dispose();
    await finish(tester);
  });

  testWidgets('touch fallback: a tap shoots, taps while reeling pull', (
    tester,
  ) async {
    await boot(tester);
    await tester.tap(find.byKey(const ValueKey('sky')));
    await tester.pump();
    expect(
      round().shotsLeft < 3 || round().phase == SkyPhase.reeling,
      isTrue,
      reason: 'the tap was a shot',
    );
    // Force a hit, then pull with taps.
    if (round().phase == SkyPhase.aiming) shoot(at: 0);
    await tester.pump();
    expect(round().phase, SkyPhase.reeling);
    for (var i = 0; i < 4; i++) {
      await tester.tap(find.byKey(const ValueKey('sky')));
      await tester.pump();
    }
    expect(round().phase, SkyPhase.resolved);
    expect(session().phase, SessionPhase.feedback);
    await finish(tester);
  });

  testWidgets('a tap scores at the arrow position at tap time (no latency '
      'compensation); the same time with latency would differ', (tester) async {
    await boot(tester);
    final r = round();
    bool hitsAt(Duration t) {
      final x = r.field.arrowX(t);
      return [
        for (var i = 0; i < question().choices.length; i++)
          (r.field.answerX(i, t) - x).abs() <= r.hitRadius - 0.02,
      ].any((b) => b);
    }

    bool missesAt(Duration t) {
      final x = r.field.arrowX(t);
      return [
        for (var i = 0; i < question().choices.length; i++)
          (r.field.answerX(i, t) - x).abs() > r.hitRadius + 0.02,
      ].every((b) => b);
    }

    // Wait until the arrow is on an answer now but was not one latency ago.
    await tester.runAsync(
      () => h.run(
        const Duration(seconds: 120),
        stopWhen: () {
          final f = h.controller.frameClock;
          return hitsAt(f) && missesAt(f - r.castLatency);
        },
      ),
    );
    final f = h.controller.frameClock;
    expect(hitsAt(f) && missesAt(f - r.castLatency), isTrue);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sky')));
    await tester.pump();
    expect(round().phase, SkyPhase.reeling, reason: 'scored at tap time');
    await finish(tester);
  });

  testWidgets('the arrow and the answers move with the pose clock', (
    tester,
  ) async {
    await boot(tester);
    final before = tester.getCenter(find.byKey(const ValueKey('arrow'))).dx;
    await tester.runAsync(() => h.run(const Duration(milliseconds: 500)));
    await tester.pump();
    final after = tester.getCenter(find.byKey(const ValueKey('arrow'))).dx;
    expect(after, isNot(closeTo(before, 0.5)));
    await finish(tester);
  });

  testWidgets('4 answers fit a small landscape phone (800x360)', (
    tester,
  ) async {
    await boot(tester, size: const Size(800, 360), level: _four);
    expect(question().choices, hasLength(4));
    expect(tester.takeException(), isNull);
    final rects = [
      for (var i = 0; i < 4; i++)
        tester.getRect(find.byKey(ValueKey('answer-$i'))),
    ]..sort((a, b) => a.left.compareTo(b.left));
    for (var i = 1; i < rects.length; i++) {
      expect(rects[i].left, greaterThan(rects[i - 1].right));
    }
    await finish(tester);
  });

  for (final size in const [Size(800, 360), Size(1280, 720)]) {
    final label = '${size.width.toInt()}x${size.height.toInt()}';
    testWidgets(
      'guidance and miss text are Play 28 sp, no overflow at $label',
      (tester) async {
        await boot(tester, size: size, level: _four);
        expect(tester.takeException(), isNull);
        final guide = find.text('Nhảy hoặc chạm để bắn');
        expect(guide, findsOneWidget);
        expect(tester.widget<Text>(guide).style!.fontSize, 28);
        expect(tester.getRect(guide).right, lessThanOrEqualTo(size.width));

        shoot(); // a miss
        await tester.pump();
        expect(tester.takeException(), isNull);
        final miss = find.byKey(const ValueKey('miss-note'));
        expect(tester.widget<Text>(miss).style!.fontSize, 28);
        expect(tester.getRect(miss).right, lessThanOrEqualTo(size.width));
        await finish(tester);
      },
    );
  }

  testWidgets('PlayScreen routes a skyShoot question to SkyShootScreen', (
    tester,
  ) async {
    await boot(tester, useScreen: false);
    expect(find.byType(SkyShootScreen), findsOneWidget);
    await finish(tester);
  });
}
