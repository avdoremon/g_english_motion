import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/modes/catch_it.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/session/level_session.dart';
import 'package:g_english_motion/ui/screens/catch_it_screen.dart';
import 'package:g_english_motion/ui/screens/lane_jump_screen.dart';
import 'package:g_english_motion/ui/screens/play_header.dart';
import 'package:g_english_motion/ui/screens/play_screen.dart';
import 'package:g_english_motion/ui/shell/hold_ring.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';

import '../helpers/game_harness.dart';
import '../helpers/hold_screen_rig.dart' show holdWords;

void main() {
  late GameHarness h;

  Future<void> boot(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
    bool reduceMotion = false,
    bool routed = false,
    ModeKind mode = ModeKind.catchIt,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      h = await GameHarness.create(
        words: holdWords,
        modes: [mode],
        mode: mode,
        withImages: true,
      );
      await h.startAndCalibrate();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: routed
              ? PlayScreen(controller: h.controller)
              : CatchItScreen(controller: h.controller),
        ),
      ),
    );
    expect(h.controller.session!.phase, SessionPhase.playing);
  }

  Future<void> advance(WidgetTester tester, Duration d) async {
    await tester.runAsync(() => h.run(d));
    await tester.pump();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(h.dispose);
  }

  LevelSession session() => h.controller.session!;
  CatchItRound round() => session().round as CatchItRound;
  ChoiceQuestion q() => session().current.question as ChoiceQuestion;
  String wordOf(int i) => h.controller.itemFor(q().choices[i].itemId).word;
  Finder pic(int i) => find.byKey(ValueKey('catch-pic-$i'));
  Finder lane(int i) => find.byKey(ValueKey('catch-lane-$i'));

  List<String> semanticLabels(WidgetTester tester) {
    final out = <String>[];
    void walk(SemanticsNode n) {
      if (n.label.isNotEmpty) out.add(n.label);
      n.visitChildren((c) {
        walk(c);
        return true;
      });
    }

    walk(
      tester
          .binding
          .renderViews
          .first
          .owner!
          .semanticsOwner!
          .rootSemanticsNode!,
    );
    return out;
  }

  testWidgets('fits 800x360 and 1280x720; lanes and pictures >= 56 dp', (
    tester,
  ) async {
    for (final size in const [Size(800, 360), Size(1280, 720)]) {
      await boot(tester, size: size);
      expect(find.byType(CatchItScreen), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        for (final f in [lane(i), pic(i)]) {
          final s = tester.getSize(f);
          expect(s.width, greaterThanOrEqualTo(56), reason: '$size $i');
          expect(s.height, greaterThanOrEqualTo(56), reason: '$size $i');
        }
      }
      await advance(tester, const Duration(seconds: 8));
      expect(tester.takeException(), isNull, reason: '$size');
      await tester.runAsync(
        () => h.run(
          const Duration(seconds: 40),
          stopWhen: () => session().phase == SessionPhase.feedback,
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$size feedback');
      await tester.pump(const Duration(seconds: 6));
      await finish(tester);
    }
  });

  testWidgets('play text is >= 28 sp (Label 24 only in the header)', (
    tester,
  ) async {
    await boot(tester);
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final size = DefaultTextStyle.of(tester.element(find.byWidget(t))).style
          .merge(t.style)
          .fontSize!;
      final inHeader = find
          .ancestor(of: find.byWidget(t), matching: find.byType(PlayHeader))
          .evaluate()
          .isNotEmpty;
      expect(
        size,
        greaterThanOrEqualTo(inHeader ? 24 : 28),
        reason: '"${t.data}"',
      );
    }
    expect(find.text('Nghe nhé'), findsOneWidget);
    expect(find.byIcon(Icons.volume_up), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the answer word is nowhere before the result', (tester) async {
    final sem = tester.ensureSemantics();
    await boot(tester);
    final word = wordOf(q().correctIndex);
    await advance(tester, const Duration(seconds: 3));
    expect(round().result, isNull);
    bool leaks(String s) => s.toLowerCase().contains(word.toLowerCase());
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      expect(leaks(t.data ?? ''), isFalse, reason: 'text "${t.data}"');
    }
    for (final l in semanticLabels(tester)) {
      expect(leaks(l), isFalse, reason: 'semantics "$l"');
    }
    expect(
      h.captions.where(h.controller.shouldShowCaption).where(leaks),
      isEmpty,
      reason: 'displayed captions',
    );
    // After the result the word is revealed.
    await tester.runAsync(
      () => h.run(
        const Duration(seconds: 40),
        stopWhen: () => session().phase == SessionPhase.feedback,
      ),
    );
    await tester.pump();
    expect(find.text(word), findsWidgets);
    await tester.pump(const Duration(seconds: 6));
    sem.dispose();
    await finish(tester);
  });

  testWidgets('tapping a lane or picture does not grade the round', (
    tester,
  ) async {
    await boot(tester);
    final lane0 = h.controller.selectedLane;
    for (var i = 0; i < 3; i++) {
      await tester.tap(lane(i), warnIfMissed: false);
      await tester.tap(pic(i), warnIfMissed: false);
    }
    await tester.pump();
    expect(round().result, isNull);
    expect(session().phase, SessionPhase.playing);
    expect(h.controller.selectedLane, lane0);
    await advance(tester, const Duration(seconds: 2));
    expect(round().result, isNull);
    await finish(tester);
  });

  testWidgets('player and highlight follow the round lane, from one source', (
    tester,
  ) async {
    await boot(tester);
    for (final l in [0, 2, 1]) {
      h.controller.debugInject(LaneChanged(l, at: Duration.zero));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(round().lane, l);
      final px = tester.getCenter(find.byKey(const ValueKey('catch-player')));
      expect(px.dx, closeTo(tester.getCenter(lane(l)).dx, 1));
      final box = tester.widget<DecoratedBox>(
        find.descendant(of: lane(l), matching: find.byType(DecoratedBox)).first,
      );
      expect((box.decoration as BoxDecoration).color, AppTheme.selectedFill);
      for (final o in [0, 1, 2].where((o) => o != l)) {
        final b = tester.widget<DecoratedBox>(
          find
              .descendant(of: lane(o), matching: find.byType(DecoratedBox))
              .first,
        );
        expect(
          (b.decoration as BoxDecoration).color,
          isNot(AppTheme.selectedFill),
        );
      }
    }
    await finish(tester);
  });

  testWidgets('the fall follows fallFraction and freezes while lost', (
    tester,
  ) async {
    await boot(tester);
    final top0 = tester.getTopLeft(pic(0)).dy;
    await advance(tester, const Duration(seconds: 10));
    expect(round().fallFraction, closeTo(0.5, 0.06));
    final mid = tester.getTopLeft(pic(0)).dy;
    expect(mid, greaterThan(top0));

    // Lost: the clock stops, so do the pictures.
    h.controller.debugInject(PlayerLost(at: Duration.zero));
    await tester.pump();
    final frozen = tester.getTopLeft(pic(0)).dy;
    final frac = round().fallFraction;
    await tester.runAsync(
      () => h.run(const Duration(seconds: 3), withFrames: false),
    );
    await tester.pump();
    expect(round().fallFraction, frac);
    expect(tester.getTopLeft(pic(0)).dy, frozen);

    // Back: it carries on to the catch line, ending at the bottom.
    h.controller.debugInject(PlayerFound(at: Duration.zero));
    await tester.runAsync(
      () => h.run(
        const Duration(seconds: 40),
        stopWhen: () => session().phase == SessionPhase.feedback,
      ),
    );
    await tester.pump();
    final end = tester.getTopLeft(pic(0)).dy;
    expect(end, greaterThan(mid));
    expect(
      (mid - top0) / (end - top0),
      closeTo(0.5, 0.1),
      reason: 'half the time = about half the way',
    );
    expect(
      tester.getBottomLeft(pic(0)).dy,
      lessThanOrEqualTo(
        tester.getTopLeft(find.byKey(const ValueKey('catch-player'))).dy + 1,
      ),
    );
    await tester.pump(const Duration(seconds: 6));
    await finish(tester);
  });

  testWidgets('reduce-motion: pictures stay put, a countdown ring shows', (
    tester,
  ) async {
    await boot(tester, reduceMotion: true);
    expect(find.byKey(const ValueKey('catch-countdown')), findsOneWidget);
    final top = tester.getTopLeft(pic(1)).dy;
    final ring0 = tester.widget<HoldRing>(
      find.byKey(const ValueKey('catch-countdown')),
    );
    await advance(tester, const Duration(seconds: 8));
    expect(tester.getTopLeft(pic(1)).dy, top);
    final ring1 = tester.widget<HoldRing>(
      find.byKey(const ValueKey('catch-countdown')),
    );
    expect(ring1.progress, greaterThan(ring0.progress));
    // Still playable: standing in the right lane at the catch line is correct.
    h.lane = q().correctIndex;
    await tester.runAsync(
      () => h.run(
        const Duration(seconds: 40),
        stopWhen: () => session().phase == SessionPhase.feedback,
      ),
    );
    await tester.pump();
    expect(session().lastResult, RoundResult.correct);
    expect(find.byKey(const ValueKey('catch-countdown')), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await finish(tester);
  });

  testWidgets('PlayScreen routes catchIt here, laneJump still to LaneJump', (
    tester,
  ) async {
    await boot(tester, routed: true);
    expect(find.byKey(const ValueKey('mode-catchIt')), findsOneWidget);
    expect(find.byType(CatchItScreen), findsOneWidget);
    expect(find.byType(LaneJumpScreen), findsNothing);
    await finish(tester);

    await boot(tester, routed: true, mode: ModeKind.laneJump);
    expect(find.byKey(const ValueKey('mode-laneJump')), findsOneWidget);
    expect(find.byType(LaneJumpScreen), findsOneWidget);
    expect(find.byType(CatchItScreen), findsNothing);
    await finish(tester);
  });
}
