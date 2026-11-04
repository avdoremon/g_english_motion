import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/progress/progress_store.dart';
import 'package:g_english_motion/speech/speech_source.dart';
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
  }) async {
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
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

  testWidgets('grade 3 is playable; grades 4-5 are "Sắp có"', (tester) async {
    await pump(tester);
    for (final g in [4, 5]) {
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
    for (final g in [1, 2, 3]) {
      expect(
        find.descendant(
          of: find.byKey(ValueKey('grade-$g')),
          matching: find.text('Sắp có'),
        ),
        findsNothing,
      );
    }
    await tester.tap(find.byKey(const ValueKey('grade-3')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('play')));
    expect(played.last, (3, 1));
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
