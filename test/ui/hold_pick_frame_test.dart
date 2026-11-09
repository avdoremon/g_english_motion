import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/ui/screens/balloon_pop_screen.dart';
import 'package:g_english_motion/ui/screens/hold_pick_frame.dart';
import 'package:g_english_motion/ui/screens/memory_flip_screen.dart';

import '../helpers/hold_screen_rig.dart';

void main() {
  final rig = HoldRig(
    ModeKind.memoryFlip,
    2,
    (c, clock) => MemoryFlipScreen(key: const ValueKey('a'), controller: c),
  );

  testWidgets('a mode switch keeps the layout of the screen that replaced '
      'the old one', (tester) async {
    await rig.boot(tester);
    final c = rig.h.controller;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: BalloonPopScreen(key: const ValueKey('b'), controller: c),
        ),
      ),
    );
    // The old screen disposed after the new one set its layout.
    final frame = tester.getRect(find.byType(HoldPickFrame));
    final prompt = tester.widget<HoldPickFrame>(find.byType(HoldPickFrame));
    final top = frame.top + prompt.promptHeight + 8;
    final centre = rig.round.targetRect(0).center;
    expect(
      Offset(
        frame.left + centre.dx * frame.width,
        top + centre.dy * (frame.bottom - top),
      ),
      offsetMoreOrLessEquals(tester.getCenter(rig.choice(0)), epsilon: 1.5),
    );
    // Out-of-range choices never throw.
    expect(rig.round.targetRect(0), isNot(Rect.zero));
    await rig.finish(tester);
  });

  testWidgets('disposing a frame that never laid out leaves the layout alone', (
    tester,
  ) async {
    await rig.boot(tester);
    final c = rig.h.controller;
    // Built (so it has state) but its layout fails (unbounded height), so the
    // board never builds and no layout is reported. Drain those errors.
    await tester.pumpWidget(
      MaterialApp(
        home: CustomScrollView(
          slivers: [
            SliverOffstage(
              offstage: true,
              sliver: SliverToBoxAdapter(
                child: HoldPickFrame(
                  controller: c,
                  round: rig.round,
                  promptHeight: 40,
                  promptBuilder: (_, _) => const SizedBox(),
                  layout: (i, n, board) => Rect.zero,
                  itemBuilder: (_, _, _, _) => const SizedBox(),
                  semanticLabel: (_, _) => '',
                ),
              ),
            ),
          ],
        ),
      ),
    );
    while (tester.takeException() != null) {}
    const mine = Rect.fromLTWH(0.1, 0.2, 0.3, 0.4);
    c.setHoldLayout((_) => mine);
    await tester.pumpWidget(const SizedBox());
    expect(rig.round.targetRect(0), mine);
  });
}
