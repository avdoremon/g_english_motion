import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/session/level_session.dart';
import 'package:g_english_motion/ui/mascot/tin_tin.dart';
import 'package:g_english_motion/ui/screens/result_screen.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';

LevelOutcome _o(int stars, {int correct = 6, int total = 8}) => LevelOutcome(
  correct: correct,
  total: total,
  points: correct * 100,
  stars: stars,
  unlockedNext: stars >= 1,
);

void main() {
  late int again, next;

  Future<void> pump(WidgetTester tester, LevelOutcome o) async {
    again = next = 0;
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: ResultScreen(
            outcome: o,
            onPlayAgain: () => again++,
            onNext: () => next++,
          ),
        ),
      ),
    );
  }

  for (final s in [0, 1, 2, 3]) {
    testWidgets('$s stars: $s filled and ${3 - s} outlined icons', (
      tester,
    ) async {
      await pump(tester, _o(s));
      expect(find.byIcon(Icons.star), findsNWidgets(s));
      expect(find.byIcon(Icons.star_border), findsNWidgets(3 - s));
      await tester.pump(const Duration(seconds: 6));
    });
  }

  testWidgets('shows correct/total and points, Tin Tin cheers from 1 star', (
    tester,
  ) async {
    await pump(tester, _o(2));
    expect(find.textContaining('6/8'), findsOneWidget);
    expect(find.textContaining('600'), findsOneWidget);
    expect(tester.widget<TinTin>(find.byType(TinTin)).state, TinTinState.cheer);
    await tester.pump(const Duration(seconds: 6));
  });

  testWidgets('0 stars: sad Tin Tin, encouragement, next goes back home', (
    tester,
  ) async {
    await pump(tester, _o(0, correct: 2));
    expect(tester.widget<TinTin>(find.byType(TinTin)).state, TinTinState.sad);
    expect(find.text('Tiếp tục'), findsNothing);
    await tester.tap(find.text('Về trang chính'));
    expect(next, 1);
  });

  testWidgets('buttons call their callbacks and are at least 56 dp', (
    tester,
  ) async {
    await pump(tester, _o(3, correct: 8));
    await tester.tap(find.text('Chơi lại'));
    await tester.tap(find.text('Tiếp tục'));
    expect((again, next), (1, 1));
    for (final b in tester.widgetList(find.byType(FilledButton))) {
      expect(tester.getSize(find.byWidget(b)).height, greaterThanOrEqualTo(56));
    }
    await tester.pump(const Duration(seconds: 6));
  });
}
