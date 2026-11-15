import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/content_repository.dart';
import 'package:g_english_motion/input/confirm_gesture.dart';
import 'package:g_english_motion/progress/progress_store.dart';
import 'package:g_english_motion/ui/parent/parent_gate.dart';
import 'package:g_english_motion/ui/parent/parent_settings.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../helpers/game_harness.dart';

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

/// WCAG 2.x contrast ratio of two opaque colours.
double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

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

    testWidgets('wrong count and lockout survive leaving and re-entering', (
      tester,
    ) async {
      final timers = <_FakeTimer>[];
      final lockout = GateLockout(
        timerFactory: (d, cb) {
          final t = _FakeTimer(cb);
          timers.add(t);
          return t;
        },
      );
      addTearDown(lockout.dispose);
      Widget gate() => _app(
        ParentGate(
          rng: _FixedRandom(0), // 3 x 3 = 9
          lockout: lockout,
          child: const Text('S'),
        ),
      );
      Future<void> wrong() async {
        await _tapDigits(tester, '1');
        await tester.tap(find.byKey(const ValueKey('key-ok')));
        await tester.pump(const Duration(seconds: 1));
      }

      await tester.pumpWidget(gate());
      await wrong();
      await wrong();
      expect(lockout.wrongCount, 2);
      // Leave (new tree), come back: the third wrong answer still locks.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(gate());
      expect(find.text('Chờ vài giây rồi thử lại'), findsNothing);
      await wrong();
      expect(timers, hasLength(1));
      expect(find.text('Chờ vài giây rồi thử lại'), findsOneWidget);

      // Leave and come back while locked: still locked, even for 9.
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(gate());
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
      expect(find.text('Chờ vài giây rồi thử lại'), findsNothing);
      await _tapDigits(tester, '9');
      await tester.tap(find.byKey(const ValueKey('key-ok')));
      await tester.pumpAndSettle();
      expect(find.text('S'), findsOneWidget);
      expect(lockout.wrongCount, 0);
    });

    testWidgets('key border has at least 3:1 contrast with surface and '
        'background', (tester) async {
      await tester.pumpWidget(
        _app(ParentGate(rng: _FixedRandom(0), child: const Text('S'))),
      );
      final key = tester.widget<FilledButton>(
        find.byKey(const ValueKey('key-5')),
      );
      final side = key.style!.side!.resolve(<WidgetState>{})!;
      final fill = key.style!.backgroundColor!.resolve(<WidgetState>{})!;
      final theme = AppTheme.dark();
      final page = theme.scaffoldBackgroundColor;
      expect(fill, theme.colorScheme.surface);
      expect(_contrast(side.color, fill), greaterThanOrEqualTo(3));
      expect(_contrast(side.color, page), greaterThanOrEqualTo(3));
    });

    testWidgets('icon keys have semantic labels', (tester) async {
      await tester.pumpWidget(
        _app(ParentGate(rng: _FixedRandom(0), child: const Text('S'))),
      );
      final h = tester.ensureSemantics();
      await tester.pump();
      for (final l in ['Xóa', 'Xác nhận']) {
        expect(find.bySemanticsLabel(l), findsOneWidget);
        final n = tester.getSemantics(find.bySemanticsLabel(l));
        expect(n.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      }
      // Performing the semantic tap on the confirm key submits the answer.
      tester.semantics.tap(find.semantics.byLabel('Xác nhận'));
      await tester.pump();
      expect(find.text('Chưa đúng'), findsOneWidget);
      await tester.pump(const Duration(seconds: 1));
      h.dispose();
    });
  });

  group('ParentSettings', () {
    late ProgressStore store;
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      store = ProgressStore(await SharedPreferences.getInstance());
    });

    var sayItAsked = 0;
    Widget settings() => _app(
      SingleChildScrollView(
        child: ParentSettings(
          store: store,
          grades: const [1, 2],
          unitCounts: const {1: 3, 2: 2},
          onSayItTurnedOn: () async => sayItAsked++,
        ),
      ),
    );

    testWidgets('forRepo covers grades 1-5 with the repo unit counts', (
      tester,
    ) async {
      final counts = {1: 16, 2: 16, 3: 20, 4: 20, 5: 20};
      final repo = ContentRepository([
        for (final e in counts.entries)
          for (var i = 1; i <= e.value; i++)
            harnessUnit(grade: e.key, index: i, count: 4),
      ]);
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        _app(
          SingleChildScrollView(
            child: ParentSettings.forRepo(store: store, repo: repo),
          ),
        ),
      );
      for (var g = 1; g <= 5; g++) {
        expect(find.byKey(ValueKey('unit-inc-$g')), findsOneWidget);
      }
      final inc5 = find.byKey(const ValueKey('unit-inc-5'));
      for (var i = 0; i < 11; i++) {
        await tester.ensureVisible(inc5);
        await tester.tap(inc5);
        await tester.pump();
      }
      expect(store.currentUnit(5), 12);
      expect(find.text('Lớp 5: bài 12'), findsOneWidget);
      for (var i = 0; i < 30; i++) {
        await tester.tap(inc5);
        await tester.pump();
      }
      expect(store.currentUnit(5), 20);
      await tester.pumpAndSettle();
    });

    testWidgets('turning SayIt on (only on) asks for the microphone', (
      tester,
    ) async {
      sayItAsked = 0;
      await tester.pumpWidget(settings());
      final toggle = find.byKey(const ValueKey('toggle-sayit'));
      // A fresh install starts off: nothing was asked of the OS yet.
      expect(store.sayItEnabled, isFalse);
      expect(sayItAsked, 0);
      await tester.tap(toggle); // off -> on
      await tester.pump();
      expect(store.sayItEnabled, isTrue);
      expect(sayItAsked, 1);
      await tester.tap(toggle); // on -> off
      await tester.pump();
      expect(store.sayItEnabled, isFalse);
      expect(sayItAsked, 1, reason: 'switching off asks nothing');
      await tester.pumpAndSettle();
    });

    testWidgets('Theo Pup switch defaults off, explains it is experimental '
        'and persists', (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(settings());
      final toggle = find.byKey(const ValueKey('toggle-puppysays'));
      expect(toggle, findsOneWidget);
      expect(find.textContaining('Trò Theo Pup (thử nghiệm)'), findsOneWidget);
      expect(find.textContaining('thử nghiệm, có thể'), findsOneWidget);
      expect(store.puppySaysEnabled, isFalse);
      expect(tester.widget<SwitchListTile>(toggle).value, isFalse);
      await tester.tap(toggle);
      await tester.pump();
      expect(store.puppySaysEnabled, isTrue);
      expect(tester.widget<SwitchListTile>(toggle).value, isTrue);
      await tester.tap(toggle);
      await tester.pump();
      expect(store.puppySaysEnabled, isFalse);
      await tester.pumpAndSettle();
    });

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

      expect(store.sayItEnabled, isFalse);
      await tester.tap(find.byKey(const ValueKey('toggle-sayit')));
      await tester.pump();
      expect(store.sayItEnabled, isTrue);
      await tester.pumpAndSettle();
    });

    testWidgets('stepper nodes are unique, tappable and change the unit', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(settings());
      expect(find.bySemanticsLabel('Giảm bài lớp 1'), findsOneWidget);
      expect(find.bySemanticsLabel('Tăng bài lớp 2'), findsOneWidget);
      final node = tester.getSemantics(find.bySemanticsLabel('Tăng bài lớp 1'));
      expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
      tester.semantics.tap(find.semantics.byLabel('Tăng bài lớp 1'));
      await tester.pump();
      expect(store.currentUnit(1), 2);
      tester.semantics.tap(find.semantics.byLabel('Giảm bài lớp 1'));
      await tester.pump();
      expect(store.currentUnit(1), 1);
      h.dispose();
    });

    testWidgets('stepper buttons show a tooltip yet stay one semantic node', (
      tester,
    ) async {
      final h = tester.ensureSemantics();
      await tester.pumpWidget(settings());
      expect(find.byTooltip('Tăng bài lớp 1'), findsOneWidget);
      expect(find.byTooltip('Giảm bài lớp 2'), findsOneWidget);
      // The label is announced once (the tooltip adds no second node)...
      expect(find.bySemanticsLabel('Tăng bài lớp 1'), findsOneWidget);
      // ...and a long press shows the visible tooltip text.
      await tester.longPress(find.byKey(const ValueKey('unit-inc-1')));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Tăng bài lớp 1'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      h.dispose();
    });

    testWidgets('shows labels and a privacy note that does not pretend to be '
        'a link', (tester) async {
      await tester.pumpWidget(settings());
      expect(find.text('Chế độ không nhảy (giơ hai tay)'), findsOneWidget);
      final note = find.textContaining('quyền riêng tư');
      expect(note, findsOneWidget);
      final style = tester.widget<Text>(note).style;
      expect(
        style?.decoration,
        isNot(TextDecoration.underline),
        reason: 'nothing may look tappable while nothing happens on a tap',
      );
      expect(style?.color, isNot(AppTheme.accent));
      // And it really is not tappable: no gesture detector around it.
      expect(
        find.ancestor(of: note, matching: find.byType(InkWell)),
        findsNothing,
      );
      expect(
        find.ancestor(of: note, matching: find.byType(GestureDetector)),
        findsNothing,
      );
    });
  });
}
