import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/ui/mascot/tin_tin.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';

void main() {
  test('AppTheme palette and dark theme', () {
    expect(AppTheme.background, const Color(0xFF1B1F4B));
    expect(AppTheme.surface, const Color(0xFF262B6B));
    expect(AppTheme.accent, const Color(0xFF35D0FF));
    expect(AppTheme.yellow, const Color(0xFFFFD23F));
    expect(AppTheme.green, const Color(0xFF3DDC97));
    expect(AppTheme.coral, const Color(0xFFFF6B6B));
    expect(AppTheme.pink, AppTheme.coral);
    expect(AppTheme.ink, const Color(0xFF0E1033));
    expect(AppTheme.surfaceLight, const Color(0xFF323896));
    expect(AppTheme.orange, const Color(0xFFFFB84D));
    expect(AppTheme.purple, const Color(0xFF6C4DFF));
    expect(AppTheme.text, const Color(0xFFFFFFFF));
    expect(AppTheme.muted, const Color(0xFFC9CCF5));
    final t = AppTheme.dark();
    expect(t.brightness, Brightness.dark);
    expect(t.scaffoldBackgroundColor, AppTheme.background);
    expect(t.textTheme.bodyLarge!.fontSize, greaterThanOrEqualTo(28));
    expect(t.textTheme.bodyLarge!.fontFamily, 'Baloo 2');
  });

  test('type scale has exactly five sizes', () {
    final sizes = {
      AppTheme.textStyles.display,
      AppTheme.textStyles.title,
      AppTheme.textStyles.heading,
      AppTheme.textStyles.play,
      AppTheme.textStyles.label,
    }.map((s) => s.fontSize).toSet();
    expect(sizes, {56.0, 48.0, 36.0, 28.0, 24.0});
  });

  testWidgets('every themed button reaches the 56 dp target, outlined too', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: Column(
            children: [
              FilledButton(onPressed: () {}, child: const Text('A')),
              OutlinedButton(onPressed: () {}, child: const Text('B')),
            ],
          ),
        ),
      ),
    );
    for (final f in [find.byType(FilledButton), find.byType(OutlinedButton)]) {
      expect(
        tester.getSize(f).height,
        greaterThanOrEqualTo(AppTheme.minTarget),
        reason: '$f',
      );
    }
    final style = AppTheme.dark().outlinedButtonTheme.style;
    expect(style, isNotNull);
    expect(style!.textStyle?.resolve({})?.fontSize, greaterThanOrEqualTo(28));
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

  testWidgets('disableAnimations renders cheer static (settles at once)', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: MaterialApp(home: TinTin(state: TinTinState.cheer)),
      ),
    );
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('pulse replays cheer; mascot is repaint-isolated', (
    tester,
  ) async {
    Widget app(int p) => MaterialApp(
      home: TinTin(state: TinTinState.cheer, pulse: p),
    );
    await tester.pumpWidget(app(0));
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
    await tester.pumpWidget(app(1));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(TinTin),
        matching: find.byType(RepaintBoundary),
      ),
      findsWidgets,
    );
    await tester.pumpWidget(const SizedBox());
  });
}
