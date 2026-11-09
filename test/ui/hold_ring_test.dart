import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/ui/shell/hold_ring.dart';

void main() {
  testWidgets('HoldRing is 56 dp by default, silent and ignores pointers', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: HoldRing(progress: 0.5)),
      ),
    );
    expect(tester.getSize(find.byType(HoldRing)), const Size(56, 56));
    expect(find.byType(IgnorePointer), findsWidgets);
    expect(tester.getSemantics(find.byType(HoldRing)).label, isEmpty);
    handle.dispose();
  });

  testWidgets('HoldRing takes a size and any progress without error', (
    tester,
  ) async {
    for (final p in [-1.0, 0.0, 0.3, 1.0, 2.0]) {
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: HoldRing(progress: p, size: 80)),
        ),
      );
      expect(tester.getSize(find.byType(HoldRing)), const Size(80, 80));
    }
  });
}
