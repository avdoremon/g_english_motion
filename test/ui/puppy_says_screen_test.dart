import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/action_config.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/action_detector.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/session/level_session.dart';
import 'package:g_english_motion/ui/mascot/tin_tin.dart';
import 'package:g_english_motion/ui/screens/lane_jump_screen.dart';
import 'package:g_english_motion/ui/screens/play_header.dart';
import 'package:g_english_motion/ui/screens/play_screen.dart';
import 'package:g_english_motion/ui/screens/puppy_says_screen.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';

import '../helpers/game_harness.dart';
import '../helpers/map_asset_bundle.dart';

void main() {
  late GameHarness h;
  late ActionConfig config;

  setUpAll(() async {
    config = await ActionConfig.load(
      MapAssetBundle({
        ActionConfig.assetPath: File(ActionConfig.assetPath).readAsStringSync(),
      }),
    );
  });

  Future<void> boot(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
    double textScale = 1.0,
    bool reduceMotion = false,
    bool routed = false,
    int seed = 7,
    VoidCallback? onExit,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      h = await GameHarness.create(
        mode: ModeKind.puppySays,
        hangTts: true,
        seed: seed,
        actions: config,
        puppySaysEnabled: true,
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
              : PuppySaysScreen(controller: h.controller, onExit: onExit),
        ),
      ),
    );
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(h.dispose);
  }

  LevelSession session() => h.controller.session!;
  ActionQuestion q() => session().current.question as ActionQuestion;

  Future<void> startPlaying(WidgetTester tester) async {
    session().onPromptFinished();
    await tester.pump();
    expect(session().phase, SessionPhase.playing);
  }

  Future<void> doIt(WidgetTester tester) async {
    h.controller.debugInject(ActionPerformed(q().action, at: h.lastFrameAt));
    await tester.pump();
  }

  Future<void> runOut(WidgetTester tester) async {
    await tester.runAsync(
      () => h.run(session().round.timeLimit + const Duration(seconds: 1)),
    );
    await tester.pump();
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

  Finder command() => find.byKey(const ValueKey('puppy-command'));

  for (final size in const [Size(800, 360), Size(1280, 720)]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('no overflow, all parts present and on screen at '
          '${size.width.toInt()}x${size.height.toInt()} scale $scale', (
        tester,
      ) async {
        await boot(tester, size: size, textScale: scale);
        await startPlaying(tester);
        expect(tester.takeException(), isNull);
        expect(find.byKey(const ValueKey('puppy-mascot')), findsOneWidget);
        expect(find.byType(TinTin), findsOneWidget);
        expect(find.byKey(const ValueKey('puppy-pictogram')), findsOneWidget);
        expect(find.byKey(const ValueKey('puppy-countdown')), findsOneWidget);
        expect(find.byType(PlayHeader), findsOneWidget);
        expect(tester.widget<Text>(command()).data, q().command);
        for (final k in const [
          'puppy-mascot',
          'puppy-pictogram',
          'puppy-countdown',
          'puppy-command',
        ]) {
          final r = tester.getRect(find.byKey(ValueKey(k)));
          expect(r.left, greaterThanOrEqualTo(0), reason: k);
          expect(r.top, greaterThanOrEqualTo(0), reason: k);
          expect(r.right, lessThanOrEqualTo(size.width), reason: k);
          expect(r.bottom, lessThanOrEqualTo(size.height), reason: k);
        }
        // Both verdict states must fit as well (hint can wrap on a timeout).
        await doIt(tester);
        expect(tester.takeException(), isNull);
        await tester.pump(const Duration(seconds: 6));
        await finish(tester);

        await boot(tester, size: size, textScale: scale);
        await startPlaying(tester);
        await runOut(tester);
        expect(tester.takeException(), isNull);
        final hint = tester.getRect(find.byKey(const ValueKey('puppy-hint')));
        expect(hint.bottom, lessThanOrEqualTo(size.height));
        expect(hint.right, lessThanOrEqualTo(size.width));
        await tester.pump(const Duration(seconds: 6));
        await finish(tester);
      });
    }
  }

  testWidgets('every Text is >= 28 sp (24 only in the header)', (tester) async {
    await boot(tester);
    await startPlaying(tester);
    await runOut(tester);
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final size = DefaultTextStyle.of(tester.element(find.byWidget(t))).style
          .merge(t.style)
          .fontSize!;
      final inHeader = find
          .ancestor(of: find.byWidget(t), matching: find.byType(PlayHeader))
          .evaluate()
          .isNotEmpty;
      expect(size, greaterThanOrEqualTo(inHeader ? 24 : 28), reason: t.data);
    }
    expect(
      tester.widget<Text>(command()).style!.fontSize,
      greaterThanOrEqualTo(36),
    );
    await tester.pump(const Duration(seconds: 6));
    await finish(tester);
  });

  testWidgets('the pictogram is a Material icon matching the action', (
    tester,
  ) async {
    for (final seed in [1, 2, 3, 4, 5, 6]) {
      await boot(tester, seed: seed);
      final icon = find.descendant(
        of: find.byKey(const ValueKey('puppy-pictogram')),
        matching: find.byType(Icon),
      );
      expect(
        tester.widget<Icon>(icon).icon,
        PuppySaysScreen.iconFor(q().action),
      );
      await finish(tester);
    }
    final icons = {
      for (final a in PuppyAction.values) PuppySaysScreen.iconFor(a),
    };
    expect(icons, hasLength(PuppyAction.values.length));
  });

  testWidgets('no camera image and no touch answer', (tester) async {
    await boot(tester);
    await startPlaying(tester);
    expect(find.byType(Image), findsNothing);
    expect(find.byType(InkWell), findsNothing);
    expect(find.byType(GestureDetector), findsNothing);
    await tester.tap(command(), warnIfMissed: false);
    await tester.tap(find.byKey(const ValueKey('puppy-pictogram')));
    await tester.pump();
    expect(session().lastResult, isNull);
    expect(session().phase, SessionPhase.playing);
    await finish(tester);
  });

  testWidgets('correct shows Giỏi lắm! and never Sai', (tester) async {
    await boot(tester);
    await startPlaying(tester);
    // No verdict text exists before the result.
    expect(find.text('Giỏi lắm!'), findsNothing);
    expect(find.text('Sai'), findsNothing);
    await doIt(tester);
    expect(session().lastResult, RoundResult.correct);
    expect(find.text('Giỏi lắm!'), findsOneWidget);
    expect(find.text('Sai'), findsNothing);
    expect(find.byKey(const ValueKey('puppy-hint')), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await finish(tester);
  });

  testWidgets('timeout shows Hết giờ and the Vietnamese hint, never Sai', (
    tester,
  ) async {
    await boot(tester);
    await startPlaying(tester);
    expect(find.byKey(const ValueKey('puppy-hint')), findsNothing);
    await runOut(tester);
    expect(session().lastResult, RoundResult.timeout);
    expect(find.text('Hết giờ'), findsOneWidget);
    expect(
      tester.widget<Text>(find.byKey(const ValueKey('puppy-hint'))).data,
      q().hintVi,
    );
    expect(find.text('Sai'), findsNothing);
    expect(find.textContaining('Sai'), findsNothing);
    expect(find.text('Chưa đúng'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await finish(tester);
  });

  testWidgets('the countdown bar drains with the round clock', (tester) async {
    await boot(tester);
    await startPlaying(tester);
    double width() => tester
        .getSize(find.byKey(const ValueKey('puppy-countdown-fill')))
        .width;
    final full = width();
    await tester.runAsync(() => h.run(session().round.timeLimit * 0.5));
    await tester.pump();
    expect(width(), closeTo(full / 2, full * 0.05));
    await finish(tester);
  });

  testWidgets('semantics: the command names the action, nothing says wrong', (
    tester,
  ) async {
    final sem = tester.ensureSemantics();
    await boot(tester);
    await startPlaying(tester);
    final labels = semanticLabels(tester);
    expect(labels, contains('Pup nói: ${q().command}. ${q().hintVi}'));
    expect(labels, contains(TinTin.semanticsLabel(TinTinState.idle)));
    await runOut(tester);
    final after = semanticLabels(tester);
    expect(after.any((l) => l.contains('Hết giờ')), isTrue);
    expect(after.any((l) => l.toLowerCase().contains('sai')), isFalse);
    sem.dispose();
    await tester.pump(const Duration(seconds: 6));
    await finish(tester);
  });

  testWidgets('reduce-motion renders and finishes without animation', (
    tester,
  ) async {
    await boot(tester, reduceMotion: true, size: const Size(800, 360));
    await startPlaying(tester);
    await doIt(tester);
    expect(tester.takeException(), isNull);
    expect(session().phase, SessionPhase.feedback);
    await tester.pump(const Duration(seconds: 6));
    await finish(tester);
  });

  testWidgets('exit button calls onExit and is >= 56 dp', (tester) async {
    var exits = 0;
    await boot(tester, onExit: () => exits++);
    final r = tester.getRect(find.byKey(const ValueKey('exit')));
    expect(r.shortestSide, greaterThanOrEqualTo(56));
    await tester.tap(find.byKey(const ValueKey('exit')));
    expect(exits, 1);
    await finish(tester);
  });

  testWidgets('PlayScreen routes puppySays here, not to LaneJump', (
    tester,
  ) async {
    await boot(tester, routed: true);
    expect(find.byKey(const ValueKey('mode-puppySays')), findsOneWidget);
    expect(find.byType(PuppySaysScreen), findsOneWidget);
    expect(find.byType(LaneJumpScreen), findsNothing);
    await finish(tester);
  });
}
