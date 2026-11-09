import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/session/level_session.dart';
import 'package:g_english_motion/ui/screens/balloon_pop_screen.dart';
import 'package:g_english_motion/ui/screens/hold_pick_frame.dart';
import 'package:g_english_motion/ui/screens/play_screen.dart';

import '../helpers/hold_screen_rig.dart';

void main() {
  final rig = HoldRig(
    ModeKind.balloonPop,
    3,
    (c, clock) => BalloonPopScreen(controller: c, clock: clock),
  );

  testWidgets('fits 800x360 and 1280x720 without overflow', (tester) async {
    for (final size in const [Size(800, 360), Size(1280, 720)]) {
      await rig.boot(tester, size: size);
      expect(find.byKey(const ValueKey('prompt-picture')), findsOneWidget);
      await rig.advance(tester, const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: '$size');
      await rig.finish(tester);
    }
  });

  testWidgets('balloons show their words; each target >= 56 dp with gaps', (
    tester,
  ) async {
    for (final size in const [Size(800, 360), Size(1280, 720)]) {
      await rig.boot(tester, size: size);
      final n = rig.question.choices.length;
      expect(n, inInclusiveRange(3, 5));
      for (var i = 0; i < n; i++) {
        expect(find.text(rig.wordOf(i)), findsOneWidget);
        final s = tester.getSize(rig.choice(i));
        expect(s.width, greaterThanOrEqualTo(56), reason: '$size balloon $i');
        expect(s.height, greaterThanOrEqualTo(56), reason: '$size balloon $i');
        if (i > 0) {
          expect(
            tester.getTopLeft(rig.choice(i)).dx,
            greaterThan(tester.getTopRight(rig.choice(i - 1)).dx),
          );
        }
      }
      await rig.finish(tester);
    }
  });

  testWidgets('all text is at least 28 sp', (tester) async {
    await rig.boot(tester);
    for (final t in tester.widgetList<Text>(find.byType(Text))) {
      final size = DefaultTextStyle.of(tester.element(find.byWidget(t))).style
          .merge(t.style)
          .fontSize!;
      expect(size, greaterThanOrEqualTo(28), reason: '"${t.data}"');
    }
    await rig.finish(tester);
  });

  testWidgets('no answer leak: nothing marks the right balloon before the '
      'result', (tester) async {
    final handle = tester.ensureSemantics();
    await rig.boot(tester);
    for (var i = 0; i < rig.question.choices.length; i++) {
      expect(
        tester.getSemantics(rig.choice(i)).label,
        rig.wordOf(i),
        reason: 'balloon $i is announced by its word only',
      );
    }
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.text('Đúng'), findsNothing);
    // The spoken word would give the answer away: no caption for it.
    expect(rig.h.controller.shouldShowCaption(rig.correctWord), isFalse);
    handle.dispose();
    await rig.finish(tester);
  });

  testWidgets('tapping the right balloon pops it: Đúng', (tester) async {
    final handle = tester.ensureSemantics();
    await rig.boot(tester);
    final i = rig.question.correctIndex;
    await tester.tap(rig.choice(i));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(rig.round.chosenIndex, i);
    expect(rig.session.phase, SessionPhase.feedback);
    expect(rig.session.lastResult, RoundResult.correct);
    expect(find.text('Đúng'), findsOneWidget);
    expect(find.byKey(const ValueKey('pop')), findsOneWidget);
    expect(
      tester.getSemantics(rig.choice(i)).label,
      '${rig.correctWord}, đúng',
    );
    handle.dispose();
    await rig.finish(tester);
  });

  testWidgets('tapping a wrong balloon says Sai and marks the right one', (
    tester,
  ) async {
    await rig.boot(tester);
    final i = (rig.question.correctIndex + 1) % rig.question.choices.length;
    await tester.tap(rig.choice(i));
    await tester.pump();
    expect(rig.round.chosenIndex, i);
    expect(rig.session.lastResult, RoundResult.wrong);
    expect(find.text('Sai'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await rig.finish(tester);
  });

  testWidgets('a hand held on a drawn balloon pops it (layout seam)', (
    tester,
  ) async {
    await rig.boot(tester);
    final i = rig.question.correctIndex;
    final frame = tester.getRect(find.byType(HoldPickFrame));
    final prompt = tester.widget<HoldPickFrame>(find.byType(HoldPickFrame));
    final board = Rect.fromLTRB(
      frame.left,
      frame.top + prompt.promptHeight + 8,
      frame.right,
      frame.bottom,
    );
    final c = rig.round.targetRect(i).center;
    expect(
      Offset(board.left + c.dx * board.width, board.top + c.dy * board.height),
      offsetMoreOrLessEquals(tester.getCenter(rig.choice(i)), epsilon: 1.5),
    );
    // Sweeping across the other balloons pops none of them.
    var t = rig.h.lastFrameAt;
    for (var j = 0; j < rig.question.choices.length; j++) {
      if (j == i) continue;
      final o = rig.round.targetRect(j).center;
      rig.h.controller.debugInject(CursorMoved(o.dx, o.dy, at: t));
      t += const Duration(milliseconds: 100);
    }
    expect(rig.round.result, isNull);
    for (var k = 0; k <= 14; k++) {
      rig.h.controller.debugInject(
        CursorMoved(c.dx, c.dy, at: t + Duration(milliseconds: 50 * k)),
      );
    }
    await tester.pump();
    expect(rig.round.chosenIndex, i);
    expect(rig.session.lastResult, RoundResult.correct);
    await rig.finish(tester);
  });

  testWidgets('the hand cursor ring is drawn while the hand is seen', (
    tester,
  ) async {
    await rig.boot(tester);
    expect(find.byKey(const ValueKey('hand-cursor')), findsNothing);
    final c = rig.round.targetRect(0).center;
    rig.h.controller.debugInject(
      CursorMoved(c.dx, c.dy, at: rig.h.lastFrameAt),
    );
    await rig.advance(tester, const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('hand-cursor')), findsOneWidget);
    await rig.finish(tester);
  });

  testWidgets('reduce motion: the pop is instant', (tester) async {
    await rig.boot(tester, reduceMotion: true);
    await tester.tap(rig.choice(rig.question.correctIndex));
    await tester.pump();
    final pop = tester.widget<Transform>(
      find
          .ancestor(
            of: find.byKey(const ValueKey('pop')),
            matching: find.byType(Transform),
          )
          .first,
    );
    expect(pop.transform.getMaxScaleOnAxis(), 1.0);
    await rig.finish(tester);
  });

  testWidgets('PlayScreen routes balloonPop to this screen', (tester) async {
    await rig.boot(
      tester,
      routed: true,
      routedScreen: (c) => PlayScreen(controller: c),
    );
    expect(find.byKey(const ValueKey('mode-balloonPop')), findsOneWidget);
    expect(find.byType(BalloonPopScreen), findsOneWidget);
    await rig.finish(tester);
  });
}
