import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/input/confirm_gesture.dart';
import 'package:g_english_motion/progress/progress_store.dart';
import 'package:g_english_motion/ui/parent/parent_gate.dart';
import 'package:g_english_motion/ui/parent/parent_settings.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Always returns [v] so the gate question is deterministic.
class _FixedRandom implements Random {
  _FixedRandom(this.v);
  final int v;
  @override
  int nextInt(int max) => v % max;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

Widget _app(Widget child) => MaterialApp(
  theme: AppTheme.dark(),
  home: Scaffold(body: child),
);

Future<void> _tapDigits(WidgetTester t, String digits) async {
  for (final d in digits.split('')) {
    await t.tap(find.byKey(ValueKey('key-$d')));
    await t.pump();
  }
}

void main() {
  group('ParentGate', () {
    testWidgets('wrong answer keeps child hidden, right answer reveals it', (
      tester,
    ) async {
      final gate = ParentGate(
        rng: _FixedRandom(7),
        child: const Text('SECRET'),
      );
      final q = ParentGate.questionFor(_FixedRandom(7));
      await tester.pumpWidget(_app(gate));
      expect(find.text('${q.a} × ${q.b} = ?'), findsOneWidget);
      expect(find.text('SECRET'), findsNothing);

      await _tapDigits(tester, '1'); // answers are always >= 9
      await tester.tap(find.byKey(const ValueKey('key-ok')));
      await tester.pump();
      expect(find.text('Chưa đúng'), findsOneWidget);
      expect(find.text('SECRET'), findsNothing);
      await tester.pump(const Duration(seconds: 1));

      await _tapDigits(tester, '${q.answer}');
      await tester.tap(find.byKey(const ValueKey('key-ok')));
      await tester.pumpAndSettle();
      expect(find.text('SECRET'), findsOneWidget);
    });

    testWidgets('backspace removes a digit', (tester) async {
      final q = ParentGate.questionFor(_FixedRandom(7));
      await tester.pumpWidget(
        _app(ParentGate(rng: _FixedRandom(7), child: const Text('SECRET'))),
      );
      await _tapDigits(tester, '${q.answer}0');
      await tester.tap(find.byKey(const ValueKey('key-back')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('key-ok')));
      await tester.pumpAndSettle();
      expect(find.text('SECRET'), findsOneWidget);
    });
  });

  group('ParentSettings', () {
    late ProgressStore store;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = ProgressStore(await SharedPreferences.getInstance());
    });

    Widget settings() => _app(
      SingleChildScrollView(
        child: ParentSettings(
          store: store,
          grades: const [1, 2],
          unitCounts: const {1: 3, 2: 2},
        ),
      ),
    );

    testWidgets('unit stepper clamps to 1..max', (tester) async {
      await tester.pumpWidget(settings());
      expect(store.currentUnit(1), 1);
      await tester.tap(find.byKey(const ValueKey('unit-dec-1')));
      await tester.pump();
      expect(store.currentUnit(1), 1);
      for (var i = 0; i < 5; i++) {
        await tester.tap(find.byKey(const ValueKey('unit-inc-1')));
        await tester.pump();
      }
      expect(store.currentUnit(1), 3);
      await tester.tap(find.byKey(const ValueKey('unit-dec-1')));
      await tester.pump();
      expect(store.currentUnit(1), 2);
      expect(store.currentUnit(2), 1);
    });

    testWidgets('toggles persist', (tester) async {
      await tester.pumpWidget(settings());
      expect(store.confirmGesture, ConfirmGesture.jump);
      await tester.tap(find.byKey(const ValueKey('toggle-no-jump')));
      await tester.pump();
      expect(store.confirmGesture, ConfirmGesture.raiseHands);
      await tester.tap(find.byKey(const ValueKey('toggle-no-jump')));
      await tester.pump();
      expect(store.confirmGesture, ConfirmGesture.jump);

      expect(store.sayItEnabled, isTrue);
      await tester.tap(find.byKey(const ValueKey('toggle-sayit')));
      await tester.pump();
      expect(store.sayItEnabled, isFalse);
      await tester.pumpAndSettle();
    });

    testWidgets('shows labels and privacy link text', (tester) async {
      await tester.pumpWidget(settings());
      expect(find.text('Chế độ không nhảy (giơ hai tay)'), findsOneWidget);
      expect(find.text('Chính sách quyền riêng tư'), findsOneWidget);
    });
  });
}
