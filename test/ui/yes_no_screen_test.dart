import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/modes/yes_no.dart';
import 'package:g_english_motion/session/level_session.dart';
import 'package:g_english_motion/ui/screens/lane_jump_screen.dart';
import 'package:g_english_motion/ui/screens/play_header.dart';
import 'package:g_english_motion/ui/screens/play_screen.dart';
import 'package:g_english_motion/ui/screens/yes_no_screen.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';

import '../helpers/game_harness.dart';

void main() {
  late GameHarness h;

  Future<void> boot(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
    double textScale = 1.0,
    bool reduceMotion = false,
    bool routed = false,
    ModeKind mode = ModeKind.yesNo,
    VoidCallback? onExit,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      h = await GameHarness.create(
        modes: [mode],
        mode: mode,
        withImages: true,
        hangTts: true,
        seed: 7,
      );
      await h.startAndCalibrate();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: reduceMotion,
          ),
          child: child!,
        ),
        home: Scaffold(
          body: routed
              ? PlayScreen(controller: h.controller, onExit: onExit)
              : YesNoScreen(controller: h.controller, onExit: onExit),
        ),
      ),
    );
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(h.dispose);
  }

  LevelSession session() => h.controller.session!;
  ChoiceQuestion q() => session().current.question as ChoiceQuestion;
  Finder yes() => find.byKey(const ValueKey('yesno-yes'));
  Finder no() => find.byKey(const ValueKey('yesno-no'));

  Future<void> startPlaying(WidgetTester tester) async {
    session().onPromptFinished();
    await tester.pump();
    expect(session().phase, SessionPhase.playing);
  }

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

  for (final size in const [Size(800, 360), Size(1280, 720)]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('no overflow, picture + statement + 2 targets at '
          '${size.width.toInt()}x${size.height.toInt()} scale $scale', (
        tester,
      ) async {
        await boot(tester, size: size, textScale: scale);
        await startPlaying(tester);
        expect(tester.takeException(), isNull);
        expect(find.byType(YesNoScreen), findsOneWidget);
        expect(find.byKey(const ValueKey('yesno-picture')), findsOneWidget);
        expect(find.byType(ItemPicture), findsOneWidget);
        final statement = find.byKey(const ValueKey('yesno-statement'));
        expect(statement, findsOneWidget);
        expect(tester.widget<Text>(statement).data, q().promptText);
        for (final t in [yes(), no()]) {
          final r = tester.getRect(t);
          expect(r.height, greaterThanOrEqualTo(56), reason: '$size');
          expect(r.width, greaterThanOrEqualTo(56), reason: '$size');
          expect(r.right, lessThanOrEqualTo(size.width));
          expect(r.bottom, lessThanOrEqualTo(size.height));
        }
        // Targets fill the width together.
        final total = tester.getRect(yes()).width + tester.getRect(no()).width;
        expect(total, greaterThan(size.width * 0.8));
        // Statement: play style, never shrunk below 28 sp, at most 2 lines.
        final w = tester.widget<Text>(statement);
        expect(w.maxLines, 2);
        expect(
          tester.getRect(statement).bottom,
          lessThanOrEqualTo(tester.getRect(yes()).top),
        );
        // Answer, then the verdict state must fit as well.
        await tester.tap(yes());
        await tester.pump();
        expect(session().phase, SessionPhase.feedback);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 6));
        await finish(tester);
      });
    }
  }

  testWidgets('every Text is >= 28 sp (24 only in the header and hints)', (
    tester,
  ) async {
    await boot(tester);
    await startPlaying(tester);
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final size = DefaultTextStyle.of(tester.element(find.byWidget(t))).style
          .merge(t.style)
          .fontSize!;
      final inHeader = find
          .ancestor(of: find.byWidget(t), matching: find.byType(PlayHeader))
          .evaluate()
          .isNotEmpty;
      final isHint =
          t.key == const ValueKey('yesno-hint-left') ||
          t.key == const ValueKey('yesno-hint-right');
      expect(
        size,
        greaterThanOrEqualTo(inHeader || isHint ? 24 : 28),
        reason: '"${t.data}"',
      );
    }
    final statement = tester.widget<Text>(
      find.byKey(const ValueKey('yesno-statement')),
    );
    expect(statement.style!.fontSize, greaterThanOrEqualTo(28));
    await finish(tester);
  });

  testWidgets('Đúng is on the left with its hand hint, Sai on the right', (
    tester,
  ) async {
    await boot(tester);
    await startPlaying(tester);
    expect(tester.getCenter(yes()).dx, lessThan(tester.getCenter(no()).dx));
    expect(
      find.descendant(of: yes(), matching: find.text('Đúng')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: yes(), matching: find.text('giơ tay trái')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: no(), matching: find.text('Sai')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: no(), matching: find.text('giơ tay phải')),
      findsOneWidget,
    );
    await finish(tester);
  });

  testWidgets('tapping Đúng answers 0 and Sai answers 1', (tester) async {
    for (final side in [0, 1]) {
      await boot(tester);
      await startPlaying(tester);
      final correct = q().correctIndex == side;
      await tester.tap(side == 0 ? yes() : no());
      await tester.pump();
      final round = session().round as YesNoRound;
      expect(round.chosenIndex, side);
      expect(
        session().lastResult,
        correct ? RoundResult.correct : RoundResult.wrong,
      );
      await tester.pump(const Duration(seconds: 6));
      await finish(tester);
    }
  });

  testWidgets('semantics before the answer never say whether it is true', (
    tester,
  ) async {
    final sem = tester.ensureSemantics();
    await boot(tester);
    await startPlaying(tester);
    final labels = semanticLabels(tester);
    expect(labels, contains('Đúng, giơ tay trái'));
    expect(labels, contains('Sai, giơ tay phải'));
    for (final l in labels) {
      expect(l.toLowerCase(), isNot(contains('đáp án')), reason: l);
      expect(l.toLowerCase(), isNot(contains('chính xác')), reason: l);
      expect(l.toLowerCase(), isNot(contains('đúng rồi')), reason: l);
      expect(l.toLowerCase(), isNot(contains('sai rồi')), reason: l);
    }
    // Both targets look identical to a screen reader: same suffix pattern.
    final before = labels.where((l) => l.contains('giơ tay')).toList();
    expect(before, hasLength(2));
    sem.dispose();
    await finish(tester);
  });

  testWidgets('the right side is highlighted only after the answer', (
    tester,
  ) async {
    await boot(tester);
    await startPlaying(tester);
    Color? fillOf(Finder f) {
      final ink = tester.widget<Ink>(
        find.descendant(of: f, matching: find.byType(Ink)).first,
      );
      return (ink.decoration as BoxDecoration).color;
    }

    final yesBefore = fillOf(yes());
    final noBefore = fillOf(no());
    expect(find.byKey(const ValueKey('feedback-label')), findsNothing);
    expect(find.byIcon(Icons.check), findsNothing);
    await tester.tap(q().correctIndex == 0 ? no() : yes());
    await tester.pump();
    expect(session().lastResult, RoundResult.wrong);
    expect(find.byKey(const ValueKey('feedback-label')), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    final right = q().correctIndex == 0 ? yes() : no();
    expect(fillOf(right), AppTheme.green);
    expect(fillOf(right), isNot(q().correctIndex == 0 ? yesBefore : noBefore));
    await tester.pump(const Duration(seconds: 6));
    await finish(tester);
  });

  testWidgets('a correct answer shows the verdict "Đúng" check', (
    tester,
  ) async {
    await boot(tester);
    await startPlaying(tester);
    await tester.tap(q().correctIndex == 0 ? yes() : no());
    await tester.pump();
    expect(session().lastResult, RoundResult.correct);
    expect(find.byKey(const ValueKey('feedback-label')), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await finish(tester);
  });

  testWidgets('a second tap after the answer changes nothing', (tester) async {
    await boot(tester);
    await startPlaying(tester);
    await tester.tap(yes());
    await tester.pump();
    final first = (session().round as YesNoRound).chosenIndex;
    await tester.tap(no(), warnIfMissed: false);
    await tester.pump();
    expect((session().round as YesNoRound).chosenIndex, first);
    await tester.pump(const Duration(seconds: 6));
    await finish(tester);
  });

  testWidgets('reduce-motion renders and answers without animation', (
    tester,
  ) async {
    await boot(tester, reduceMotion: true, size: const Size(800, 360));
    await startPlaying(tester);
    await tester.tap(no());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(session().phase, SessionPhase.feedback);
    await tester.pump(const Duration(seconds: 6));
    await finish(tester);
  });

  testWidgets('exit button calls onExit', (tester) async {
    var exits = 0;
    await boot(tester, onExit: () => exits++);
    await tester.tap(find.byKey(const ValueKey('exit')));
    expect(exits, 1);
    await finish(tester);
  });

  testWidgets('PlayScreen routes yesNo here, laneJump still to LaneJump', (
    tester,
  ) async {
    await boot(tester, routed: true);
    expect(find.byKey(const ValueKey('mode-yesNo')), findsOneWidget);
    expect(find.byType(YesNoScreen), findsOneWidget);
    expect(find.byType(LaneJumpScreen), findsNothing);
    await finish(tester);

    await boot(tester, routed: true, mode: ModeKind.laneJump);
    expect(find.byKey(const ValueKey('mode-laneJump')), findsOneWidget);
    expect(find.byType(YesNoScreen), findsNothing);
    await finish(tester);
  });
}
