import 'dart:async';
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
class _SeqRandom implements Random {
  _SeqRandom(this.vs);
  final List<int> vs;
  int i = 0;
  @override
  int nextInt(int max) => vs[i++ % vs.length] % max;
  @override
  double nextDouble() => 0;
  @override
  bool nextBool() => false;
}

class _FakeTimer implements Timer {
  _FakeTimer(this.cb);
  final void Function() cb;
  bool cancelled = false;
  @override
  void cancel() => cancelled = true;
  void fire() => cb();
  @override
  bool get isActive => !cancelled;
  @override
  int get tick => 0;
}

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

  group('ParentGate extras', () {
    testWidgets('new question after a wrong answer', (tester) async {
      // 3x3 first, then 4x4.
      await tester.pumpWidget(
        _app(ParentGate(rng: _SeqRandom([0, 0, 1, 1]), child: const Text('S'))),
      );
      expect(find.text('3 × 3 = ?'), findsOneWidget);
      await _tapDigits(tester, '1');
      await tester.tap(find.byKey(const ValueKey('key-ok')));
      await tester.pump();
      expect(find.text('4 × 4 = ?'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('3 wrong answers lock the pad until the timer fires', (
      tester,
    ) async {
      final timers = <_FakeTimer>[];
      await tester.pumpWidget(
        _app(
          ParentGate(
            rng: _FixedRandom(0), // always 3 x 3 = 9
            timerFactory: (d, cb) {
              expect(d, const Duration(seconds: 5));
              final t = _FakeTimer(cb);
              timers.add(t);
              return t;
            },
            child: const Text('S'),
          ),
        ),
      );
      for (var i = 0; i < 3; i++) {
        await _tapDigits(tester, '1');
        await tester.tap(find.byKey(const ValueKey('key-ok')));
        await tester.pump(const Duration(seconds: 1));
      }
      expect(timers, hasLength(1));
      expect(find.text('Chờ vài giây rồi thử lại'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey('key-9')),
        warnIfMissed: false,
      );
      await tester.tap(
        find.byKey(const ValueKey('key-ok')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(find.text('S'), findsNothing);
      timers.single.fire();
      await tester.pump();
      await _tapDigits(tester, '9');
      await tester.tap(find.byKey(const ValueKey('key-ok')));
      await tester.pumpAndSettle();
      expect(find.text('S'), findsOneWidget);
    });

    testWidgets('icon keys have semantic labels', (tester) async {
      await tester.pumpWidget(
        _app(ParentGate(rng: _FixedRandom(0), child: const Text('S'))),
      );
      expect(find.bySemanticsLabel('Xóa'), findsOneWidget);
      expect(find.bySemanticsLabel('Xác nhận'), findsOneWidget);
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

    testWidgets('stepper buttons have semantic labels', (tester) async {
      await tester.pumpWidget(settings());
      expect(find.bySemanticsLabel('Giảm bài'), findsNWidgets(2));
      expect(find.bySemanticsLabel('Tăng bài'), findsNWidgets(2));
    });

    testWidgets('shows labels and privacy link text', (tester) async {
      await tester.pumpWidget(settings());
      expect(find.text('Chế độ không nhảy (giơ hai tay)'), findsOneWidget);
      expect(find.text('Chính sách quyền riêng tư'), findsOneWidget);
    });
  });
}
