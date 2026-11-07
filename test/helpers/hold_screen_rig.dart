// Shared rig for the memoryFlip / balloonPop screen tests.
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/app/game_controller.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/modes/hold_pick.dart';
import 'package:g_english_motion/session/level_session.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';

import 'game_harness.dart';

const holdWords = ['cat', 'cap', 'cut', 'cot', 'car', 'bat', 'bag', 'big'];

class HoldRig {
  HoldRig(this.mode, this.grade, this.screen);

  final ModeKind mode;
  final int grade;
  final Widget Function(GameController c, Duration Function() clock) screen;
  late GameHarness h;

  LevelSession get session => h.controller.session!;
  HoldPickRound get round => session.round as HoldPickRound;
  ChoiceQuestion get question => session.current.question as ChoiceQuestion;
  String wordOf(int i) => h.controller.itemFor(question.choices[i].itemId).word;
  String get correctWord => wordOf(question.correctIndex);

  Future<void> boot(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
    bool reduceMotion = false,
    bool routed = false,
    Widget Function(GameController c)? routedScreen,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      h = await GameHarness.create(
        grade: grade,
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
              ? routedScreen!(h.controller)
              : screen(h.controller, () => Duration.zero),
        ),
      ),
    );
    expect(session.phase, SessionPhase.playing);
  }

  /// Plays [d] of the game clock (frames + ticks), then rebuilds.
  Future<void> advance(WidgetTester tester, Duration d) async {
    await tester.runAsync(() => h.run(d));
    await tester.pump();
  }

  /// Past the memoryFlip peek (2 s) and the flip animation.
  Future<void> endPeek(WidgetTester tester) async {
    await advance(tester, const Duration(milliseconds: 2300));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(h.dispose);
  }

  Finder choice(int i) => find.byKey(ValueKey('choice-$i'));

  /// Labels of every node of the semantics tree.
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
}
