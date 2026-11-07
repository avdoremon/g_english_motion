import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/ui/kit/kit.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';

Widget _wrap(Widget child, {double scale = 1.0, double width = 800}) =>
    MaterialApp(
      theme: AppTheme.dark(),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: w!,
      ),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    );

void main() {
  const long = 'Chơi lại từ đầu nào các bạn';

  for (final scale in [1.0, 1.3]) {
    testWidgets('BigButton long label fits, >=56 high (scale $scale)', (
      tester,
    ) async {
      final label = long.substring(0, 24);
      expect(label.length, 24);
      await tester.pumpWidget(
        _wrap(
          BigButton(label: label, onPressed: () {}, icon: Icons.replay),
          scale: scale,
          width: 200,
        ),
      );
      expect(tester.takeException(), isNull);
      final size = tester.getSize(find.byType(BigButton));
      expect(size.height, greaterThanOrEqualTo(64));
      expect(size.width, lessThanOrEqualTo(200));
      final text = find.descendant(
        of: find.byType(BigButton),
        matching: find.text(label),
      );
      expect(
        find.ancestor(of: text, matching: find.byType(FittedBox)),
        findsOneWidget,
      );
      final shown = tester.getBottomRight(text).dx - tester.getTopLeft(text).dx;
      expect(shown, lessThanOrEqualTo(size.width - 56));
      // Natural width is larger than what is shown, so it truly shrank.
      final natural = tester.getSize(text).width;
      expect(natural, greaterThan(shown));
    });

    testWidgets('all kit widgets survive text scale $scale', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Column(
            children: [
              StickerCard(tilt: -3, child: const Text('Apple')),
              RoundIconButton(
                icon: Icons.close,
                semanticLabel: 'Đóng',
                onPressed: () {},
              ),
              const StarRow(earned: 2),
              HudBar(stars: 12, timeFraction: 0.5, trailing: const Text('x')),
            ],
          ),
          scale: scale,
        ),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('BigButton semantics label, tap, disabled', (tester) async {
    final h = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _wrap(BigButton(label: 'Tiếp tục', onPressed: () => taps++)),
    );
    expect(find.bySemanticsLabel('Tiếp tục'), findsOneWidget);
    await tester.tap(find.byType(BigButton));
    expect(taps, 1);
    await tester.pumpWidget(
      _wrap(const BigButton(label: 'Tiếp tục', onPressed: null)),
    );
    await tester.tap(find.byType(BigButton));
    expect(taps, 1);
    h.dispose();
  });

  testWidgets('RoundIconButton hit area >= 56 for size 48', (tester) async {
    final h = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpWidget(
      _wrap(
        RoundIconButton(
          icon: Icons.close,
          semanticLabel: 'Đóng',
          size: 48,
          onPressed: () => taps++,
        ),
      ),
    );
    final s = tester.getSize(find.byType(RoundIconButton));
    expect(s.width, greaterThanOrEqualTo(56));
    expect(s.height, greaterThanOrEqualTo(56));
    expect(find.bySemanticsLabel('Đóng'), findsOneWidget);
    await tester.tap(find.byType(RoundIconButton));
    expect(taps, 1);
    h.dispose();
  });

  testWidgets('StarRow earned 2 of 3', (tester) async {
    await tester.pumpWidget(_wrap(const StarRow(earned: 2)));
    expect(find.byKey(const Key('star-on-0')), findsOneWidget);
    expect(find.byKey(const Key('star-on-1')), findsOneWidget);
    expect(find.byKey(const Key('star-off-2')), findsOneWidget);
    expect(find.byKey(const Key('star-on-2')), findsNothing);
  });

  testWidgets('StickerCard has 5px ink border and tilt', (tester) async {
    await tester.pumpWidget(
      _wrap(const StickerCard(tilt: 3, child: Text('hi'))),
    );
    final box = tester
        .widgetList<DecoratedBox>(
          find.descendant(
            of: find.byType(StickerCard),
            matching: find.byType(DecoratedBox),
          ),
        )
        .map((d) => d.decoration)
        .whereType<BoxDecoration>()
        .firstWhere((d) => d.border != null);
    expect(box.color, Colors.white);
    expect((box.border! as Border).top.width, 5);
    expect((box.border! as Border).top.color, AppTheme.ink);
    expect(
      find.descendant(
        of: find.byType(StickerCard),
        matching: find.byType(Transform),
      ),
      findsWidgets,
    );
  });

  testWidgets('HudBar shows star count and trailing', (tester) async {
    await tester.pumpWidget(
      _wrap(HudBar(stars: 7, timeFraction: 0.2, trailing: const Text('T'))),
    );
    expect(find.text('7'), findsOneWidget);
    expect(find.text('T'), findsOneWidget);
  });

  testWidgets('HudBar ring semantics: with and without seconds', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap(HudBar(stars: 1, timeFraction: 0.5, trailing: const SizedBox())),
    );
    expect(find.bySemanticsLabel('Thời gian còn lại'), findsOneWidget);
    await tester.pumpWidget(
      _wrap(
        HudBar(
          stars: 1,
          timeFraction: 0.5,
          seconds: 9,
          trailing: const SizedBox(),
        ),
      ),
    );
    expect(find.bySemanticsLabel('Còn 9 giây'), findsOneWidget);
  });

  testWidgets('StarRow semantics reads "N trên M sao"', (tester) async {
    await tester.pumpWidget(_wrap(const StarRow(earned: 2)));
    expect(find.bySemanticsLabel('2 trên 3 sao'), findsOneWidget);
  });

  for (final dims in [const Size(800, 360), const Size(1280, 720)]) {
    for (final n in [7, 12, 123]) {
      testWidgets('kit renders at $dims with $n stars at 1.3x', (tester) async {
        await tester.binding.setSurfaceSize(dims);
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MaterialApp(
            theme: AppTheme.dark(),
            builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: const TextScaler.linear(1.3)),
              child: w!,
            ),
            home: Scaffold(
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: HudBar(
                      stars: n,
                      timeFraction: 0.3,
                      trailing: RoundIconButton(
                        icon: Icons.close,
                        semanticLabel: 'Đóng',
                        onPressed: () {},
                      ),
                    ),
                  ),
                  BigButton(label: 'Tiếp tục', onPressed: () {}),
                ],
              ),
            ),
          ),
        );
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('StickerCard rotation matches tilt', (tester) async {
    Matrix4 m(double tilt) {
      final t = tester.widget<Transform>(
        find.descendant(
          of: find.byType(StickerCard),
          matching: find.byType(Transform),
        ),
      );
      return t.transform;
    }

    await tester.pumpWidget(
      _wrap(const StickerCard(tilt: 3, child: Text('a'))),
    );
    final r = m(3).getRotation();
    expect(
      math.atan2(r.entry(1, 0), r.entry(0, 0)),
      closeTo(3 * math.pi / 180, 1e-6),
    );
    await tester.pumpWidget(_wrap(const StickerCard(child: Text('a'))));
    expect(m(0).isIdentity(), isTrue);
  });
}
