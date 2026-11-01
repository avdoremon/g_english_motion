import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/ui/shell/caption_strip.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';

void main() {
  late StreamController<String> ctl;

  setUp(() => ctl = StreamController<String>.broadcast(sync: true));
  tearDown(() => ctl.close());

  Future<void> pump(WidgetTester tester, {bool Function(String)? filter}) =>
      tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Column(
              children: [
                const Expanded(child: SizedBox()),
                CaptionStrip(captions: ctl.stream, filter: filter),
              ],
            ),
          ),
        ),
      );

  testWidgets('shows a caption at 28 sp or more, hides it after 3 s', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(Text), findsNothing);
    ctl.add('Giỏi quá!');
    await tester.pump();
    final text = tester.widget<Text>(find.text('Giỏi quá!'));
    expect(text.style!.fontSize, greaterThanOrEqualTo(28));
    await tester.pump(const Duration(milliseconds: 2900));
    expect(find.text('Giỏi quá!'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Giỏi quá!'), findsNothing);
  });

  testWidgets('a new caption replaces the old one and restarts the timer', (
    tester,
  ) async {
    await pump(tester);
    ctl.add('một');
    await tester.pump(const Duration(seconds: 2));
    ctl.add('hai');
    await tester.pump();
    expect(find.text('một'), findsNothing);
    expect(find.text('hai'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 2500));
    expect(find.text('hai'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 600));
    expect(find.text('hai'), findsNothing);
  });

  testWidgets('captions rejected by the filter are never shown', (
    tester,
  ) async {
    await pump(tester, filter: (c) => c != 'ball');
    ctl.add('Nghe nhé');
    await tester.pump();
    ctl.add('ball');
    await tester.pump();
    expect(find.text('ball'), findsNothing);
    // The suppressed word does not even replace the visible caption.
    expect(find.text('Nghe nhé'), findsOneWidget);
  });
}
