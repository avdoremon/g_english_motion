import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/modes/mode_availability.dart';
import 'package:g_english_motion/ui/screens/mode_picker_screen.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';

void main() {
  late List<ModeKind?> picks;
  late int backs;

  setUp(() {
    picks = [];
    backs = 0;
  });

  Future<void> pump(
    WidgetTester tester, {
    int grade = 1,
    bool sayIt = false,
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
          body: ModePickerScreen(
            grade: grade,
            level: 1,
            sayItAvailable: sayIt,
            onPick: picks.add,
            onBack: () => backs++,
          ),
        ),
      ),
    );
  }

  Finder tile(ModeKind m) => find.byKey(ValueKey('mode-${m.name}'));
  bool enabled(WidgetTester t, ModeKind m) =>
      t.getSemantics(tile(m)).flagsCollection.isEnabled == Tristate.isTrue;

  testWidgets('grade 1: laneJump and catchIt enabled, balloonPop disabled', (
    tester,
  ) async {
    await pump(tester, grade: 1);
    expect(enabled(tester, ModeKind.laneJump), isTrue);
    expect(enabled(tester, ModeKind.catchIt), isTrue);
    expect(enabled(tester, ModeKind.balloonPop), isFalse);
    expect(enabled(tester, ModeKind.memoryFlip), isFalse);
    // The reason is visible: the grade range of the disabled mode.
    expect(
      find.descendant(
        of: tile(ModeKind.balloonPop),
        matching: find.text('Lớp 3–5'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('grade 4: dragSpell, skyShoot, memoryFlip, balloonPop enabled', (
    tester,
  ) async {
    await pump(tester, grade: 4);
    for (final m in [
      ModeKind.dragSpell,
      ModeKind.skyShoot,
      ModeKind.memoryFlip,
      ModeKind.balloonPop,
    ]) {
      expect(enabled(tester, m), isTrue, reason: '$m');
    }
    expect(enabled(tester, ModeKind.laneJump), isFalse);
    expect(enabled(tester, ModeKind.catchIt), isFalse);
  });

  testWidgets('tap enabled -> onPick(mode); shuffle -> onPick(null)', (
    tester,
  ) async {
    await pump(tester, grade: 4);
    await tester.tap(tile(ModeKind.memoryFlip));
    await tester.tap(find.byKey(const ValueKey('mode-shuffle')));
    expect(picks, [ModeKind.memoryFlip, null]);
  });

  testWidgets('a disabled tile does nothing', (tester) async {
    await pump(tester, grade: 1);
    await tester.tap(tile(ModeKind.balloonPop));
    expect(picks, isEmpty);
  });

  testWidgets('back button calls onBack', (tester) async {
    await pump(tester);
    await tester.tap(find.byKey(const ValueKey('picker-back')));
    expect(backs, 1);
  });

  testWidgets('SayIt tile only when available, and it picks sayIt', (
    tester,
  ) async {
    await pump(tester, grade: 1);
    expect(tile(ModeKind.sayIt), findsNothing);
    await pump(tester, grade: 1, sayIt: true);
    expect(enabled(tester, ModeKind.sayIt), isTrue);
    await tester.tap(tile(ModeKind.sayIt));
    expect(picks, [ModeKind.sayIt]);
  });

  for (final size in const [Size(1280, 720), Size(800, 360)]) {
    for (final scale in const [1.0, 1.3]) {
      testWidgets('no overflow, targets >= 56 at ${size.width.toInt()}x'
          '${size.height.toInt()} scale $scale', (tester) async {
        for (final g in [1, 4]) {
          await pump(
            tester,
            grade: g,
            sayIt: true,
            size: size,
            textScale: scale,
          );
          expect(tester.takeException(), isNull);
          for (final i in kModeInfos) {
            final key = tile(i.mode);
            await tester.ensureVisible(key);
            final r = tester.getRect(key);
            expect(r.height, greaterThanOrEqualTo(AppTheme.minTarget));
            expect(r.width, greaterThanOrEqualTo(AppTheme.minTarget));
            expect(r.right, lessThanOrEqualTo(size.width));
          }
          await tester.ensureVisible(
            find.byKey(const ValueKey('mode-shuffle')),
          );
          expect(tester.takeException(), isNull);
        }
      });
    }
  }
}
