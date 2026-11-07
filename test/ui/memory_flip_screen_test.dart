import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/session/level_session.dart';
import 'package:g_english_motion/ui/screens/hold_pick_frame.dart';
import 'package:g_english_motion/ui/screens/memory_flip_screen.dart';
import 'package:g_english_motion/ui/screens/play_screen.dart';

import '../helpers/hold_screen_rig.dart';

void main() {
  final rig = HoldRig(
    ModeKind.memoryFlip,
    2,
    (c, clock) => MemoryFlipScreen(controller: c, clock: clock),
  );

  testWidgets('fits 800x360 and 1280x720 without overflow', (tester) async {
    for (final size in const [Size(800, 360), Size(1280, 720)]) {
      await rig.boot(tester, size: size);
      expect(find.byKey(const ValueKey('prompt-picture')), findsOneWidget);
      await rig.endPeek(tester);
      expect(tester.takeException(), isNull, reason: '$size');
      await rig.finish(tester);
    }
  });

  testWidgets('3-5 cards, each target >= 56 dp, with gaps between them', (
    tester,
  ) async {
    for (final size in const [Size(800, 360), Size(1280, 720)]) {
      await rig.boot(tester, size: size);
      final n = rig.question.choices.length;
      expect(n, inInclusiveRange(3, 5));
      for (var i = 0; i < n; i++) {
        final s = tester.getSize(rig.choice(i));
        expect(s.width, greaterThanOrEqualTo(56), reason: '$size card $i');
        expect(s.height, greaterThanOrEqualTo(56), reason: '$size card $i');
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

  testWidgets('all text is at least 28 sp, before and after the peek', (
    tester,
  ) async {
    await rig.boot(tester);
    for (var phase = 0; phase < 2; phase++) {
      for (final t in tester.widgetList<Text>(find.byType(Text))) {
        final size = DefaultTextStyle.of(tester.element(find.byWidget(t))).style
            .merge(t.style)
            .fontSize!;
        expect(size, greaterThanOrEqualTo(28), reason: '"${t.data}"');
      }
      await rig.endPeek(tester);
    }
    await rig.finish(tester);
  });

  testWidgets('the cards are face-up for the peek, then face-down', (
    tester,
  ) async {
    await rig.boot(tester);
    final words = [for (var i = 0; i < 3; i++) rig.wordOf(i)];
    expect(rig.round.peeking, isTrue);
    expect(find.text('Nhớ các thẻ nhé!'), findsOneWidget);
    for (final w in words) {
      expect(find.text(w), findsOneWidget, reason: 'peek shows $w');
    }
    await rig.endPeek(tester);
    expect(rig.round.peeking, isFalse);
    expect(find.text('Tìm thẻ cùng cặp'), findsOneWidget);
    for (final w in words) {
      expect(find.text(w), findsNothing, reason: '$w is hidden');
    }
    expect(find.byIcon(Icons.star), findsWidgets);
    await rig.finish(tester);
  });

  testWidgets('no answer leak: face-down cards expose no word to semantics', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await rig.boot(tester);
    await rig.endPeek(tester);
    final labels = rig.semanticLabels(tester).join('|');
    for (var i = 0; i < rig.question.choices.length; i++) {
      expect(labels, contains('Thẻ ${i + 1}, đang úp'));
      expect(labels, isNot(contains(rig.wordOf(i))), reason: 'card $i');
    }
    expect(find.text(rig.correctWord), findsNothing);
    expect(rig.h.controller.shouldShowCaption(rig.correctWord), isFalse);
    handle.dispose();
    await rig.finish(tester);
  });

  testWidgets('during the peek the semantics read the words, none marked', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await rig.boot(tester);
    for (var i = 0; i < rig.question.choices.length; i++) {
      expect(tester.getSemantics(rig.choice(i)).label, rig.wordOf(i));
    }
    handle.dispose();
    await rig.finish(tester);
  });

  testWidgets('tapping the right card grades it correct and reveals', (
    tester,
  ) async {
    await rig.boot(tester);
    await rig.endPeek(tester);
    final i = rig.question.correctIndex;
    await tester.tap(rig.choice(i));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(rig.round.chosenIndex, i);
    expect(rig.session.phase, SessionPhase.feedback);
    expect(rig.session.lastResult, RoundResult.correct);
    expect(find.text('Đúng'), findsOneWidget);
    expect(find.text(rig.correctWord), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);
    await rig.finish(tester);
  });

  testWidgets('tapping a wrong card says Sai', (tester) async {
    await rig.boot(tester);
    await rig.endPeek(tester);
    final i = (rig.question.correctIndex + 1) % rig.question.choices.length;
    await tester.tap(rig.choice(i));
    await tester.pump(const Duration(milliseconds: 400));
    expect(rig.round.chosenIndex, i);
    expect(rig.session.lastResult, RoundResult.wrong);
    expect(find.text('Sai'), findsOneWidget);
    await rig.finish(tester);
  });

  testWidgets('a tap during the peek picks nothing', (tester) async {
    await rig.boot(tester);
    await tester.tap(rig.choice(0));
    await tester.pump();
    expect(rig.round.result, isNull);
    await rig.finish(tester);
  });

  testWidgets('a hand held on a drawn card picks it (layout seam)', (
    tester,
  ) async {
    await rig.boot(tester);
    await rig.endPeek(tester);
    final r = rig.round;
    final i = rig.question.correctIndex;
    // The board is the frame below the prompt row (and its 8 dp gap).
    final frame = tester.getRect(find.byType(HoldPickFrame));
    final prompt = tester.widget<HoldPickFrame>(find.byType(HoldPickFrame));
    final board = Rect.fromLTRB(
      frame.left,
      frame.top + prompt.promptHeight + 8,
      frame.right,
      frame.bottom,
    );
    final drawn = tester.getCenter(rig.choice(i));
    final c = r.targetRect(i).center;
    expect(
      Offset(board.left + c.dx * board.width, board.top + c.dy * board.height),
      offsetMoreOrLessEquals(drawn, epsilon: 1.5),
    );
    var t = rig.h.lastFrameAt;
    for (var k = 0; k <= 22; k++) {
      rig.h.controller.debugInject(
        CursorMoved(c.dx, c.dy, at: t + Duration(milliseconds: 50 * k)),
      );
    }
    await tester.pump();
    expect(rig.round.chosenIndex, i);
    expect(rig.session.lastResult, RoundResult.correct);
    await rig.finish(tester);
  });

  testWidgets('the hand cursor ring follows the hand once the peek is over', (
    tester,
  ) async {
    await rig.boot(tester);
    await rig.endPeek(tester);
    expect(find.byKey(const ValueKey('hand-cursor')), findsNothing);
    final c = rig.round.targetRect(0).center;
    rig.h.controller.debugInject(
      CursorMoved(c.dx, c.dy, at: rig.h.lastFrameAt),
    );
    await rig.advance(tester, const Duration(milliseconds: 100));
    expect(find.byKey(const ValueKey('hand-cursor')), findsOneWidget);
    await rig.finish(tester);
  });

  testWidgets('reduce motion: the flip is instant', (tester) async {
    await rig.boot(tester, reduceMotion: true);
    final w = rig.wordOf(0);
    expect(find.text(w), findsOneWidget);
    await rig.advance(tester, const Duration(milliseconds: 2300));
    expect(find.text(w), findsNothing, reason: 'no animation frames needed');
    await rig.finish(tester);
  });

  testWidgets('PlayScreen routes memoryFlip to this screen', (tester) async {
    await rig.boot(
      tester,
      routed: true,
      routedScreen: (c) => PlayScreen(controller: c),
    );
    expect(find.byKey(const ValueKey('mode-memoryFlip')), findsOneWidget);
    expect(find.byType(MemoryFlipScreen), findsOneWidget);
    await rig.finish(tester);
  });
}
