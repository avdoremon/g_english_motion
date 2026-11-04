import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/input/pose_types.dart';
import 'package:g_english_motion/levels/level_config.dart';
import 'package:g_english_motion/modes/drag_spell.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/session/level_session.dart';
import 'package:g_english_motion/ui/screens/drag_spell_screen.dart';
import 'package:g_english_motion/ui/screens/play_screen.dart';
import 'package:g_english_motion/ui/theme/app_theme.dart';

import '../helpers/game_harness.dart';

const _noHints = LevelConfig(
  level: 4,
  questionCount: 8,
  baseTime: Duration(seconds: 12),
  choiceCount: 4,
  hints: HintMode.none,
  window: UnitWindow.current,
);

const _partialHints = LevelConfig(
  level: 3,
  questionCount: 8,
  baseTime: Duration(seconds: 15),
  choiceCount: 4,
  hints: HintMode.partial,
  window: UnitWindow.currentPlus2,
);

void main() {
  late GameHarness h;
  var clock = Duration.zero;
  var elapsed = Duration.zero;

  Future<void> boot(
    WidgetTester tester, {
    Size size = const Size(1280, 720),
    LevelConfig level = harnessLevel,
    bool images = true,
    bool useScreen = true,
  }) async {
    clock = Duration.zero;
    elapsed = Duration.zero;
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      h = await GameHarness.create(
        grade: 3,
        modes: const [ModeKind.dragSpell],
        level: level,
        withImages: images,
      );
      await h.startAndCalibrate();
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: Scaffold(
          body: useScreen
              ? DragSpellScreen(controller: h.controller, clock: () => clock)
              : PlayScreen(controller: h.controller),
        ),
      ),
    );
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(h.dispose);
  }

  LevelSession session() => h.controller.session!;
  DragSpellRound round() => session().round as DragSpellRound;
  Question question() => session().current.question;
  String answerText() {
    final q = question();
    return q is SpellQuestion ? q.word : (q as OrderQuestion).answer.join(' ');
  }

  List<String> answerPieces() {
    final q = question();
    return q is SpellQuestion
        ? [for (final r in q.word.runes) String.fromCharCode(r)]
        : (q as OrderQuestion).answer;
  }

  Future<void> tap(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(ValueKey(key)));
    await tester.pump();
  }

  /// A camera frame (keeps the controller's frame watchdog quiet).
  void sendFrame() =>
      h.frames.add(PoseFrame([h.standing()], h.lastFrameAt + clock));

  /// Holds the (normalized) cursor on [target] for [d], 100 ms per step.
  Future<void> holdOn(WidgetTester tester, Finder target, Duration d) async {
    final size = tester.getSize(find.byType(DragSpellScreen));
    final c = tester.getCenter(target);
    for (var t = Duration.zero; t < d; t += const Duration(milliseconds: 100)) {
      clock += const Duration(milliseconds: 100);
      elapsed += const Duration(milliseconds: 100);
      h.controller.debugInject(
        CursorMoved(c.dx / size.width, c.dy / size.height, at: clock),
      );
      sendFrame();
      h.tickCtl.add(elapsed);
      await tester.pump();
    }
  }

  /// Taps the pieces of the right answer into the slots in order.
  Future<void> solveByTaps(WidgetTester tester) async {
    final used = <int>{};
    final pieces = answerPieces();
    for (var slot = 0; slot < pieces.length; slot++) {
      final i = [for (var k = 0; k < round().tiles.length; k++) k].firstWhere(
        (k) => !used.contains(k) && round().tiles[k] == pieces[slot],
      );
      used.add(i);
      await tap(tester, 'tile-$i');
      await tap(tester, 'slot-$slot');
    }
  }

  testWidgets('playing state: the round is DragSpell and the question is read '
      'aloud at the start', (tester) async {
    await boot(tester);
    expect(session().phase, SessionPhase.playing);
    expect(round(), isA<DragSpellRound>());
    expect(
      h.ttsLog,
      contains('tts:${question().ttsText}'),
      reason: 'TTS reads the word / sentence to build',
    );
    await finish(tester);
  });

  testWidgets('the asked word is not on screen, in captions or in semantics '
      'before answering', (tester) async {
    final handle = tester.ensureSemantics();
    await boot(tester);
    final word = answerText();
    expect(find.text(word), findsNothing);
    expect(h.controller.shouldShowCaption(question().ttsText), isFalse);
    expect(
      find.bySemanticsLabel(RegExp(RegExp.escape(word))),
      findsNothing,
      reason: 'no semantics node may announce the answer',
    );
    expect(find.byKey(const ValueKey('answer-reveal')), findsNothing);
    handle.dispose();
    await finish(tester);
  });

  testWidgets('hint picture is shown when hints != none', (tester) async {
    await boot(tester);
    final q = question();
    final hasPicture = q is SpellQuestion ? q.imageItemId != null : true;
    expect(hasPicture, isTrue);
    expect(find.byKey(const ValueKey('hint-picture')), findsOneWidget);
    await finish(tester);
  });

  testWidgets('no hint picture when hints == none', (tester) async {
    await boot(tester, level: _noHints);
    expect(find.byKey(const ValueKey('hint-picture')), findsNothing);
    await finish(tester);
  });

  testWidgets('partial hints: the picture appears after half of the time', (
    tester,
  ) async {
    await boot(tester, level: _partialHints);
    expect(find.byKey(const ValueKey('hint-picture')), findsNothing);
    await tester.runAsync(
      () => h.run(
        const Duration(seconds: 60),
        stopWhen: () => session().roundElapsedFraction > 0.55,
      ),
    );
    await tester.pump();
    expect(session().roundElapsedFraction, greaterThan(0.5));
    expect(find.byKey(const ValueKey('hint-picture')), findsOneWidget);
    await finish(tester);
  });

  testWidgets('holding the cursor on a tile shows the progress ring, then '
      'picks the tile up after 1 s', (tester) async {
    await boot(tester);
    expect(find.byKey(const ValueKey('hold-ring')), findsNothing);
    await holdOn(
      tester,
      find.byKey(const ValueKey('tile-0')),
      const Duration(milliseconds: 500),
    );
    final ring = find.byKey(const ValueKey('hold-ring'));
    expect(ring, findsOneWidget);
    final v1 = tester.widget<CircularProgressIndicator>(ring).value!;
    expect(v1, inInclusiveRange(0.3, 0.7));
    expect(round().carrying, isNull);
    await holdOn(
      tester,
      find.byKey(const ValueKey('tile-0')),
      const Duration(milliseconds: 700),
    );
    expect(round().carrying, round().tiles[0]);
    await finish(tester);
  });

  testWidgets('hold a tile, then hold a slot: the slot gets the tile', (
    tester,
  ) async {
    await boot(tester);
    await holdOn(
      tester,
      find.byKey(const ValueKey('tile-1')),
      const Duration(milliseconds: 1300),
    );
    expect(round().carryingTile, 1);
    await holdOn(
      tester,
      find.byKey(const ValueKey('slot-2')),
      const Duration(milliseconds: 1300),
    );
    expect(round().slots[2], round().tiles[1]);
    expect(round().carrying, isNull);
    await finish(tester);
  });

  testWidgets('a stale cursor holds nothing', (tester) async {
    await boot(tester);
    await holdOn(
      tester,
      find.byKey(const ValueKey('tile-0')),
      const Duration(milliseconds: 300),
    );
    // The hand disappears: no more CursorMoved while time passes.
    for (var i = 0; i < 20; i++) {
      clock += const Duration(milliseconds: 100);
      elapsed += const Duration(milliseconds: 100);
      sendFrame();
      h.tickCtl.add(elapsed);
      await tester.pump();
    }
    expect(round().carrying, isNull);
    expect(find.byKey(const ValueKey('hold-ring')), findsNothing);
    await finish(tester);
  });

  testWidgets('touch fallback: taps solve the question -> Đúng, answer '
      'revealed, happy Tin Tin', (tester) async {
    await boot(tester);
    await solveByTaps(tester);
    await tap(tester, 'check-button');
    expect(session().phase, SessionPhase.feedback);
    expect(session().lastResult, RoundResult.correct);
    expect(find.text('Đúng'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
    expect(find.byKey(const ValueKey('answer-reveal')), findsOneWidget);
    expect(find.text(answerText()), findsOneWidget);
    expect(h.controller.shouldShowCaption(question().ttsText), isTrue);
    await finish(tester);
  });

  testWidgets('check with empty slots does nothing; wrong order -> Sai', (
    tester,
  ) async {
    await boot(tester);
    await tap(tester, 'check-button');
    expect(session().phase, SessionPhase.playing);
    // Fill the slots with tiles in tray order (never the answer: the tiles
    // are scrambled to differ from it, but equal letters could coincide, so
    // only assert when it really is different).
    final n = round().tiles.length;
    for (var i = 0; i < n; i++) {
      await tap(tester, 'tile-$i');
      await tap(tester, 'slot-$i');
    }
    final same =
        [for (var i = 0; i < n; i++) round().tiles[i]].join('|') ==
        answerPieces().join('|');
    expect(same, isFalse);
    await tap(tester, 'check-button');
    expect(session().lastResult, RoundResult.wrong);
    expect(find.text('Sai'), findsOneWidget);
    expect(find.byIcon(Icons.cancel), findsOneWidget);
    await finish(tester);
  });

  testWidgets('tapping a filled slot picks its tile up again', (tester) async {
    await boot(tester);
    await tap(tester, 'tile-0');
    await tap(tester, 'slot-0');
    expect(round().slots[0], isNotNull);
    await tap(tester, 'slot-0');
    expect(round().slots[0], isNull);
    expect(round().carryingTile, 0);
    expect(find.byKey(const ValueKey('carrying')), findsOneWidget);
    await finish(tester);
  });

  testWidgets('fits a small landscape phone (800x360) without overflow', (
    tester,
  ) async {
    await boot(tester, size: const Size(800, 360));
    expect(tester.takeException(), isNull);
    final n = round().tiles.length;
    for (var i = 0; i < n; i++) {
      expect(
        tester.getSize(find.byKey(ValueKey('tile-$i'))).height,
        greaterThanOrEqualTo(48),
      );
      expect(
        tester.getSize(find.byKey(ValueKey('slot-$i'))).height,
        greaterThanOrEqualTo(48),
      );
    }
    await finish(tester);
  });

  testWidgets('PlayScreen routes a dragSpell question to DragSpellScreen', (
    tester,
  ) async {
    await boot(tester, useScreen: false);
    expect(find.byType(DragSpellScreen), findsOneWidget);
    await finish(tester);
  });

  testWidgets('cursor events do not rebuild listeners of the controller', (
    tester,
  ) async {
    await boot(tester);
    var notified = 0;
    h.controller.addListener(() => notified++);
    h.controller.debugInject(const CursorMoved(0.2, 0.2, at: Duration.zero));
    expect(notified, 0);
    await finish(tester);
  });
}
