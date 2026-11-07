import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/progress/progress_store.dart';
import 'package:g_english_motion/speech/speech_source.dart';
import 'package:g_english_motion/ui/kit/kit.dart';
import 'package:g_english_motion/ui/screens/home_screen.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProgressStore store;
  late List<(int, int)> played, sayItStarted;
  late int parent;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = ProgressStore(await SharedPreferences.getInstance());
    played = [];
    sayItStarted = [];
    parent = 0;
  });

  Future<void> pump(
    WidgetTester tester, {
    SpeechAvailability sayIt = SpeechAvailability.available,
    Size size = const Size(1280, 720),
    double textScale = 1.0,
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: w!,
        ),
        home: Scaffold(
          body: HomeScreen(
            store: store,
            sayItAvailability: sayIt,
            onPlay: (g, l) => played.add((g, l)),
            onSayIt: (g, l) => sayItStarted.add((g, l)),
            onOpenParent: () => parent++,
          ),
        ),
      ),
    );
  }

  int stars(WidgetTester t, int level, IconData icon) => find
      .descendant(
        of: find.byKey(ValueKey('level-$level')),
        matching: find.byIcon(icon),
      )
      .evaluate()
      .length;

  testWidgets('shows stars and lock state per level from the store', (
    tester,
  ) async {
    unawaited(store.saveStars(1, 1, 2));
    await pump(tester);
    expect(stars(tester, 1, Icons.star), 2);
    expect(stars(tester, 1, Icons.star_border), 1);
    expect(stars(tester, 2, Icons.star), 0);
    expect(stars(tester, 2, Icons.star_border), 3);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('level-1')),
        matching: find.byIcon(Icons.lock),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('level-2')),
        matching: find.byIcon(Icons.lock),
      ),
      findsNothing,
    );
    for (final l in [3, 4, 5]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('level-$l')),
          matching: find.byIcon(Icons.lock),
        ),
        findsOneWidget,
        reason: 'level $l locked',
      );
    }
  });

  testWidgets(
    'play sends the selected grade and level; locked levels ignored',
    (tester) async {
      unawaited(store.saveStars(1, 1, 1));
      await pump(tester);
      await tester.tap(find.byKey(const ValueKey('level-4')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('play')));
      expect(played.single, (
        1,
        2,
      ), reason: 'defaults to the highest unlocked level');
      await tester.tap(find.byKey(const ValueKey('level-1')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('grade-2')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('play')));
      expect(played.last, (2, 1));
    },
  );

  testWidgets('all five grades are playable and selectable', (tester) async {
    await pump(tester);
    for (final g in [1, 2, 3, 4, 5]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('grade-$g')),
          matching: find.text('Sắp có'),
        ),
        findsNothing,
      );
      await tester.tap(find.byKey(ValueKey('grade-$g')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('play')));
      expect(played.last, (g, 1));
    }
  });

  testWidgets(
    'SayIt entry: only when the device can listen on-device AND it is switched on',
    (tester) async {
      final entry = find.byKey(const ValueKey('sayit-entry'));
      for (final a in [
        SpeechAvailability.noPermission,
        SpeechAvailability.noOnDeviceRecognizer,
      ]) {
        await pump(tester, sayIt: a);
        expect(entry, findsNothing, reason: '$a');
      }
      unawaited(store.setSayItEnabled(false));
      await pump(tester);
      expect(entry, findsNothing, reason: 'switched off by the parent');
      unawaited(store.setSayItEnabled(true));
      await pump(tester);
      expect(entry, findsOneWidget);
      expect(
        find.descendant(of: entry, matching: find.text('Sắp có')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('grade-2')));
      await tester.pump();
      final h = tester.ensureSemantics();
      tester.semantics.tap(find.semantics.byLabel('Luyện nói'));
      await tester.pump();
      expect(sayItStarted, [(2, 1)], reason: 'TalkBack can activate it');
      await tester.tap(entry);
      expect(sayItStarted, [(2, 1), (2, 1)]);
      h.dispose();
      expect(played, isEmpty);
    },
  );

  testWidgets('grade and level tiles are buttons TalkBack can activate', (
    tester,
  ) async {
    unawaited(store.saveStars(1, 1, 2));
    unawaited(store.saveStars(3, 1, 1)); // unlocks level 2 of grade 3
    await pump(tester);
    final h = tester.ensureSemantics();
    for (final label in ['Lớp 3', 'Cấp 2, 0 sao']) {
      final node = tester.getSemantics(find.bySemanticsLabel(label));
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.tap),
        isTrue,
        reason: '"$label" is announced as a button, so it must act on tap',
      );
    }
    tester.semantics.tap(find.semantics.byLabel('Lớp 3'));
    await tester.pump();
    tester.semantics.tap(find.semantics.byLabel('Cấp 2, 0 sao'));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('play')));
    expect(played, [(3, 2)], reason: 'both tiles reacted to a semantics tap');
    h.dispose();
  });

  testWidgets('parent button, big text and tap targets', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('parent-button')));
    expect(parent, 1);
    expect(
      tester.getSize(find.byKey(const ValueKey('play'))).height,
      greaterThanOrEqualTo(56),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('parent-button'))).shortestSide,
      greaterThanOrEqualTo(56),
    );
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final size = DefaultTextStyle.of(tester.element(find.byWidget(t))).style
          .merge(t.style)
          .fontSize!;
      expect(size, greaterThanOrEqualTo(28), reason: t.data);
    }
  });

  void expectKitSizes(WidgetTester tester, {required double textScale}) {
    expect(tester.takeException(), isNull);
    final buttons = [
      ...find.byType(BigButton).evaluate(),
      ...find.byType(RoundIconButton).evaluate(),
    ];
    expect(buttons, isNotEmpty);
    for (final e in buttons) {
      final s = tester.getSize(find.byElementPredicate((x) => x == e));
      expect(s.width, greaterThanOrEqualTo(56), reason: '${e.widget}');
      expect(s.height, greaterThanOrEqualTo(56), reason: '${e.widget}');
    }
    for (final b in find.byType(BigButton).evaluate()) {
      for (final e
          in find
              .descendant(
                of: find.byElementPredicate((x) => x == b),
                matching: find.byType(Text),
              )
              .evaluate()) {
        final t = e.widget as Text;
        expect(t.maxLines, 1, reason: t.data);
        final fs = (t.style?.fontSize ?? 28) * textScale;
        expect(
          tester.getSize(find.byWidget(t)).height,
          lessThan(2 * fs),
          reason: '${t.data} wraps',
        );
      }
    }
  }

  for (final size in const [Size(1280, 720), Size(800, 360)]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('kit sizes, no wrap, no overflow at ${size.width.toInt()}x'
          '${size.height.toInt()} text x$scale', (tester) async {
        unawaited(store.saveStars(1, 1, 2));
        unawaited(store.setSayItEnabled(true));
        await pump(tester, size: size, textScale: scale);
        expect(find.byType(BigButton), findsNWidgets(2)); // Chơi + Luyện nói
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('sayit-entry')),
            matching: find.text('Luyện nói'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('parent-button')).evaluate().single.widget,
          isA<RoundIconButton>(),
        );
        // The Luyện nói button sits inside the screen, not past its edge.
        await tester.ensureVisible(find.byKey(const ValueKey('sayit-entry')));
        await tester.pump();
        final r = tester.getRect(find.byKey(const ValueKey('sayit-entry')));
        expect(r.right, lessThanOrEqualTo(size.width));
        expect(r.left, greaterThanOrEqualTo(0));
        expectKitSizes(tester, textScale: scale);
      });
    }
  }

  for (final size in const [Size(1280, 720), Size(800, 360)]) {
    testWidgets('no overflow at ${size.width.toInt()}x${size.height.toInt()}', (
      tester,
    ) async {
      unawaited(store.saveStars(1, 1, 2));
      await pump(tester, size: size);
      expect(find.text('Tin Tin English'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // Everything is reachable: Play can be scrolled into view and tapped.
      await tester.ensureVisible(find.byKey(const ValueKey('play')));
      await tester.tap(find.byKey(const ValueKey('play')));
      expect(played, isNotEmpty);
    });
  }
}
