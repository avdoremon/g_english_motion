import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/progress/progress_store.dart';
import 'package:g_english_motion/ui/screens/home_screen.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late ProgressStore store;
  late List<(int, int)> played;
  late int parent;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = ProgressStore(await SharedPreferences.getInstance());
    played = [];
    parent = 0;
  });

  Future<void> pump(WidgetTester tester, {bool sayIt = true}) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: HomeScreen(
            store: store,
            sayItAvailable: sayIt,
            onPlay: (g, l) => played.add((g, l)),
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

  testWidgets('grades 3-5 are disabled with "Sắp có"', (tester) async {
    await pump(tester);
    for (final g in [3, 4, 5]) {
      final tile = find.byKey(ValueKey('grade-$g'));
      expect(
        find.descendant(of: tile, matching: find.text('Sắp có')),
        findsOneWidget,
      );
      await tester.tap(tile);
      await tester.pump();
    }
    await tester.tap(find.byKey(const ValueKey('play')));
    expect(played.single.$1, 1, reason: 'a disabled grade is never selected');
    for (final g in [1, 2]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('grade-$g')),
          matching: find.text('Sắp có'),
        ),
        findsNothing,
      );
    }
  });

  testWidgets(
    'SayIt entry: hidden when unavailable or switched off, else a "Sắp có" placeholder',
    (tester) async {
      await pump(tester, sayIt: false);
      expect(find.byKey(const ValueKey('sayit-entry')), findsNothing);
      unawaited(store.setSayItEnabled(false));
      await pump(tester);
      expect(find.byKey(const ValueKey('sayit-entry')), findsNothing);
      unawaited(store.setSayItEnabled(true));
      await pump(tester);
      final entry = find.byKey(const ValueKey('sayit-entry'));
      expect(entry, findsOneWidget);
      expect(
        find.descendant(of: entry, matching: find.text('Sắp có')),
        findsOneWidget,
      );
      await tester.tap(entry);
      expect(played, isEmpty);
    },
  );

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
}
