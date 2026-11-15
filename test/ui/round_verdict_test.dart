import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/ui/screens/round_verdict.dart';

Widget _host(RoundVerdict v) => MaterialApp(
  home: Scaffold(body: Center(child: v)),
);

void main() {
  testWidgets('a null result shows the default label, not the wrong override', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        const RoundVerdict(
          result: null,
          correctLabel: 'Chính xác',
          wrongLabel: 'Chưa đúng',
        ),
      ),
    );
    expect(find.text('Chưa đúng'), findsNothing);
    expect(find.text(RoundVerdict.labelFor(null)), findsOneWidget);
  });

  testWidgets('overrides apply to correct and wrong, never to timeout', (
    tester,
  ) async {
    for (final (r, text) in [
      (RoundResult.correct, 'Chính xác'),
      (RoundResult.wrong, 'Chưa đúng'),
      (RoundResult.timeout, 'Hết giờ'),
    ]) {
      await tester.pumpWidget(
        _host(
          RoundVerdict(
            result: r,
            correctLabel: 'Chính xác',
            wrongLabel: 'Chưa đúng',
          ),
        ),
      );
      expect(find.text(text), findsOneWidget, reason: '$r');
    }
  });
}
