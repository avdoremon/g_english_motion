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
      expect(size.height, greaterThanOrEqualTo(56));
      expect(size.width, lessThanOrEqualTo(200));
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
}
