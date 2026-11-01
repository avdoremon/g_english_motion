import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/levels/level_config.dart';
import 'package:g_english_motion/session/level_session.dart';
import 'package:g_english_motion/ui/mascot/tin_tin.dart';
import 'package:g_english_motion/ui/screens/lane_jump_screen.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';

import '../helpers/game_harness.dart';

void main() {
  late GameHarness h;

  Future<void> boot(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      h = await GameHarness.create();
      await h.startAndCalibrate();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(body: LaneJumpScreen(controller: h.controller)),
      ),
    );
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(h.dispose);
  }

  ChoiceQuestion q() =>
      h.controller.session!.current.question as ChoiceQuestion;
  Finder lane(int i) => find.byKey(ValueKey('lane-$i'));

  testWidgets('shows exactly choiceCount lanes with pictures or words', (
    tester,
  ) async {
    await boot(tester);
    expect(lane(0), findsOneWidget);
    expect(lane(1), findsOneWidget);
    expect(lane(2), findsOneWidget);
    expect(lane(3), findsNothing);
    final words = {
      for (final c in q().choices)
        c.itemId: harnessWords[int.parse(c.itemId.split('i').last)],
    };
    for (var i = 0; i < 3; i++) {
      final c = q().choices[i];
      final w = words[c.itemId]!;
      final expected = c.showWord ? w : w[0].toUpperCase();
      expect(
        find.descendant(of: lane(i), matching: find.text(expected)),
        findsWidgets,
        reason: 'lane $i',
      );
    }
    await finish(tester);
  });

  testWidgets('highlights the selected lane and marks "Em ở đây" there only', (
    tester,
  ) async {
    await boot(tester);
    for (final l in [0, 2, 1]) {
      h.controller.debugInject(LaneChanged(l, at: Duration.zero));
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        expect(tester.widget<LaneTile>(lane(i)).selected, i == l);
      }
      expect(find.text('Em ở đây'), findsOneWidget);
      expect(
        find.descendant(of: lane(l), matching: find.text('Em ở đây')),
        findsOneWidget,
      );
    }
    await finish(tester);
  });

  testWidgets('header: level, progress and score; prompt for the form', (
    tester,
  ) async {
    await boot(tester);
    expect(find.text('Cấp 1'), findsOneWidget);
    expect(find.text('1/8'), findsOneWidget);
    expect(find.byKey(const ValueKey('score')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('score')),
        matching: find.text('0'),
      ),
      findsOneWidget,
    );
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(
      find.byType(CircularProgressIndicator),
      findsOneWidget,
      reason: 'timer ring',
    );
    switch (q().form) {
      case QuestionForm.seePicturePickWord:
        expect(find.byKey(const ValueKey('prompt-picture')), findsOneWidget);
      default:
        expect(find.byIcon(Icons.volume_up), findsOneWidget);
    }
    await finish(tester);
  });

  testWidgets('correct answer: "Đúng" with a check icon, happy Tin Tin', (
    tester,
  ) async {
    await boot(tester);
    await tester.runAsync(() => h.answerInLane(q().correctIndex));
    await tester.pump();
    final label = find.byKey(const ValueKey('feedback-label'));
    expect(
      find.descendant(of: label, matching: find.text('Đúng')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: label, matching: find.byIcon(Icons.check_circle)),
      findsOneWidget,
    );
    expect(tester.widget<TinTin>(find.byType(TinTin)).state, TinTinState.happy);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('score')),
        matching: find.text('100'),
      ),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 6));
    await finish(tester);
  });

  testWidgets('wrong answer: "Sai" with a cancel icon, sad Tin Tin', (
    tester,
  ) async {
    await boot(tester);
    await tester.runAsync(() => h.answerInLane((q().correctIndex + 1) % 3));
    await tester.pump();
    final label = find.byKey(const ValueKey('feedback-label'));
    expect(
      find.descendant(of: label, matching: find.text('Sai')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: label, matching: find.byIcon(Icons.cancel)),
      findsOneWidget,
    );
    expect(tester.widget<TinTin>(find.byType(TinTin)).state, TinTinState.sad);
    await tester.pump(const Duration(seconds: 6));
    await finish(tester);
  });

  testWidgets('fits a small landscape phone (800x360) without overflow', (
    tester,
  ) async {
    await boot(tester, size: const Size(800, 360));
    expect(tester.takeException(), isNull);
    await tester.runAsync(() => h.answerInLane(0));
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 6));
    await finish(tester);
  });

  testWidgets('the see-picture prompt picture is at least 72 px on 800x360 '
      'and 1280x720', (tester) async {
    for (final size in const [Size(800, 360), Size(1280, 720)]) {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        for (var seed = 0; seed < 80; seed++) {
          h = await GameHarness.create(withImages: true, seed: seed);
          await h.startAndCalibrate();
          if (h.controller.session!.current.question.form ==
              QuestionForm.seePicturePickWord) {
            return;
          }
          await h.dispose();
        }
        fail('no seed starts with a seePicturePickWord question');
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: LaneJumpScreen(controller: h.controller)),
        ),
      );
      final pic = tester.getSize(find.byKey(const ValueKey('prompt-picture')));
      expect(pic.width, greaterThanOrEqualTo(72), reason: '$size');
      expect(pic.height, greaterThanOrEqualTo(72), reason: '$size');
      expect(tester.takeException(), isNull);
      await finish(tester);
    }
  });

  testWidgets('lane words render at full size (no shrinking)', (tester) async {
    for (final (size, min) in const [
      (Size(1280, 720), 28.0),
      (Size(800, 360), 24.0),
    ]) {
      await boot(tester, size: size);
      final lanes = q().choices;
      var checked = 0;
      for (var i = 0; i < lanes.length; i++) {
        if (!lanes[i].showWord) continue;
        final word = find.descendant(of: lane(i), matching: find.byType(Text));
        expect(
          tester.getSize(word.first).height,
          greaterThanOrEqualTo(min),
          reason: '$size lane $i',
        );
        checked++;
      }
      // Picture lanes: the placeholder letter is at least 48 px wide.
      for (var i = 0; i < lanes.length; i++) {
        if (!lanes[i].showPicture) continue;
        expect(
          tester
              .getSize(
                find.descendant(
                  of: lane(i),
                  matching: find.byType(ItemPicture),
                ),
              )
              .width,
          greaterThanOrEqualTo(48),
        );
        checked++;
      }
      expect(checked, 3);
      await finish(tester);
    }
  });

  testWidgets('all text is at least 28 sp', (tester) async {
    await boot(tester);
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final size = DefaultTextStyle.of(tester.element(find.byWidget(t))).style
          .merge(t.style)
          .fontSize!;
      expect(size, greaterThanOrEqualTo(28), reason: '"${t.data}"');
    }
    await finish(tester);
  });

  group('picture hints on word lanes (LevelConfig.hints)', () {
    LevelConfig levelWith(HintMode m) => LevelConfig(
      level: 1,
      questionCount: 8,
      baseTime: const Duration(seconds: 20),
      choiceCount: 3,
      hints: m,
      window: UnitWindow.current,
    );

    /// Boots a harness (with item pictures) whose first question is a
    /// listen-and-pick-word one, then lets the prompt finish so the clock
    /// runs.
    Future<void> bootHint(
      WidgetTester tester,
      HintMode mode, {
      Size size = const Size(1280, 720),
    }) async {
      await tester.binding.setSurfaceSize(size);
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        for (var seed = 0; seed < 60; seed++) {
          h = await GameHarness.create(
            level: levelWith(mode),
            withImages: true,
            seed: seed,
          );
          await h.startAndCalibrate();
          final first = h.controller.session!.current.question;
          if (first.form == QuestionForm.listenPickWord) {
            await h.run(const Duration(milliseconds: 300));
            return;
          }
          await h.dispose();
        }
        fail('no seed starts with a listenPickWord question');
      });
      expect(
        h.controller.session!.phase,
        SessionPhase.playing,
        reason: 'the clock should be running',
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: LaneJumpScreen(controller: h.controller)),
        ),
      );
    }

    Finder pictures() => find.descendant(
      of: find.byType(LaneTile),
      matching: find.byType(ItemPicture),
    );

    Future<void> elapse(WidgetTester tester, Duration d) async {
      await tester.runAsync(() => h.run(d));
      await tester.pump();
    }

    void expectWordsOnEveryLane() {
      for (var i = 0; i < 3; i++) {
        final c = q().choices[i];
        final w = harnessWords[int.parse(c.itemId.split('i').last)];
        expect(
          find.descendant(of: lane(i), matching: find.text(w)),
          findsOneWidget,
          reason: 'lane $i keeps its word',
        );
      }
    }

    testWidgets('the default level 1 hints are full', (tester) async {
      final levels = await tester.runAsync(() => LevelConfig.load(rootBundle));
      expect(levels!.first.hints, HintMode.full);
    });

    testWidgets('full: every lane shows its picture with the word from the '
        'start', (tester) async {
      await bootHint(tester, HintMode.full);
      expect(h.controller.session!.round.elapsedFraction, lessThan(0.1));
      expect(pictures(), findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        expect(
          find.descendant(of: lane(i), matching: find.byType(ItemPicture)),
          findsOneWidget,
        );
      }
      expectWordsOnEveryLane();
      await finish(tester);
    });

    testWidgets('partial: pictures appear after 50% of the time limit', (
      tester,
    ) async {
      await bootHint(tester, HintMode.partial);
      expect(pictures(), findsNothing);
      expectWordsOnEveryLane();
      await elapse(tester, const Duration(seconds: 8)); // ~ 40%
      expect(h.controller.session!.round.elapsedFraction, lessThan(0.5));
      expect(pictures(), findsNothing);
      await elapse(tester, const Duration(seconds: 3)); // ~ 55%
      expect(h.controller.session!.round.elapsedFraction, greaterThan(0.5));
      expect(pictures(), findsNWidgets(3));
      expectWordsOnEveryLane();
      await finish(tester);
    });

    testWidgets('none: pictures never appear', (tester) async {
      await bootHint(tester, HintMode.none);
      expect(pictures(), findsNothing);
      await elapse(tester, const Duration(seconds: 15));
      expect(h.controller.session!.round.elapsedFraction, greaterThan(0.6));
      expect(pictures(), findsNothing);
      expectWordsOnEveryLane();
      await finish(tester);
    });

    testWidgets('hint pictures are on all options and never mark the answer', (
      tester,
    ) async {
      await bootHint(tester, HintMode.full);
      // Every tile looks the same: only the player's own lane differs, and
      // that marker is independent of the right answer.
      final a = q().correctIndex;
      for (var i = 0; i < 3; i++) {
        final t = tester.widget<LaneTile>(lane(i));
        expect(t.isAnswer, isFalse, reason: 'lane $i');
        expect(t.showHintPicture, isTrue, reason: 'lane $i (answer is $a)');
      }
      expect(find.byIcon(Icons.check_circle), findsNothing);
      await finish(tester);
    });

    testWidgets('full hints fit a small landscape phone (800x360)', (
      tester,
    ) async {
      await bootHint(tester, HintMode.full, size: const Size(800, 360));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(pictures(), findsNWidgets(3));
      for (var i = 0; i < 3; i++) {
        final word = find.descendant(of: lane(i), matching: find.byType(Text));
        expect(
          tester.getSize(word.first).height,
          greaterThanOrEqualTo(24),
          reason: 'word on lane $i not shrunk',
        );
      }
      await finish(tester);
    });

    testWidgets('the hint picture is at least 48 px on 800x360 and 1280x720, '
        'words stay >= 28 sp', (tester) async {
      for (final size in const [Size(800, 360), Size(1280, 720)]) {
        await bootHint(tester, HintMode.full, size: size);
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$size');
        expect(pictures(), findsNWidgets(3));
        for (var i = 0; i < 3; i++) {
          final pic = tester.getSize(pictures().at(i));
          expect(pic.width, greaterThanOrEqualTo(48), reason: '$size lane $i');
          expect(pic.height, greaterThanOrEqualTo(48), reason: '$size lane $i');
          final word = find.descendant(
            of: lane(i),
            matching: find.byType(Text),
          );
          final style = DefaultTextStyle.of(tester.element(word.first)).style
              .merge(tester.widget<Text>(word.first).style);
          expect(style.fontSize, greaterThanOrEqualTo(28));
        }
        await finish(tester);
      }
    });

    testWidgets('all text stays >= 28 sp with hints', (tester) async {
      await bootHint(tester, HintMode.full);
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final size = DefaultTextStyle.of(tester.element(find.byWidget(t))).style
            .merge(t.style)
            .fontSize!;
        expect(size, greaterThanOrEqualTo(28), reason: '"${t.data}"');
      }
      await finish(tester);
    });

    testWidgets('picture-based forms are unaffected by the hint mode', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1280, 720));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        for (var seed = 0; seed < 60; seed++) {
          h = await GameHarness.create(
            level: levelWith(HintMode.none),
            withImages: true,
            seed: seed,
          );
          await h.startAndCalibrate();
          if (h.controller.session!.current.question.form ==
              QuestionForm.listenPickPicture) {
            return;
          }
          await h.dispose();
        }
        fail('no seed starts with a listenPickPicture question');
      });
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(body: LaneJumpScreen(controller: h.controller)),
        ),
      );
      // Picture lanes keep their pictures even with hints off.
      expect(pictures(), findsNWidgets(3));
      expect(
        find.descendant(of: lane(0), matching: find.byType(Text)),
        findsNothing,
      );
      await finish(tester);
    });
  });
}
