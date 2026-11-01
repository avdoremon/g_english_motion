import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
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
}
