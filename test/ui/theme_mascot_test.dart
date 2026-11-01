import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/ui/mascot/tin_tin.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';

void main() {
  test('AppTheme palette and dark theme', () {
    expect(AppTheme.background, const Color(0xFF14123A));
    expect(AppTheme.surface, const Color(0xFF2A2770));
    expect(AppTheme.accent, const Color(0xFF4DE1FF));
    expect(AppTheme.yellow, const Color(0xFFFFD84D));
    expect(AppTheme.green, const Color(0xFF5CF2A0));
    expect(AppTheme.pink, const Color(0xFFFF5CAA));
    expect(AppTheme.orange, const Color(0xFFFF8A5B));
    expect(AppTheme.purple, const Color(0xFF7B61FF));
    expect(AppTheme.text, const Color(0xFFFFFFFF));
    expect(AppTheme.muted, const Color(0xFFC9C6F5));
    final t = AppTheme.dark();
    expect(t.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, AppTheme.background);
    expect(t.textTheme.bodyLarge!.fontSize, greaterThanOrEqualTo(28));
    expect(t.textTheme.bodyLarge!.fontFamily, 'Baloo 2');
  });

  for (final s in TinTinState.values) {
    testWidgets('TinTin renders $s with semantics and settles', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Center(child: TinTin(state: s)),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.bySemanticsLabel(TinTin.semanticsLabel(s)), findsOneWidget);
      // Bounded animations must finish; idle ones never schedule frames.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle(
        const Duration(milliseconds: 100),
        EnginePhase.sendSemanticsUpdate,
        const Duration(seconds: 30),
      );
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('TinTin semantics labels differ per state', (tester) async {
    final labels = {
      for (final s in TinTinState.values) TinTin.semanticsLabel(s),
    };
    expect(labels.length, TinTinState.values.length);
  });

  testWidgets('TinTin changing state does not throw', (tester) async {
    Widget app(TinTinState s) => MaterialApp(home: TinTin(state: s, size: 100));
    await tester.pumpWidget(app(TinTinState.idle));
    await tester.pumpWidget(app(TinTinState.dance));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpWidget(app(TinTinState.happy));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('cheer/dance cycle is at most 1.5 s', () {
    expect(TinTin.cycle, lessThanOrEqualTo(const Duration(milliseconds: 1500)));
    expect(TinTin.cycle, greaterThan(const Duration(milliseconds: 333)));
  });
}
