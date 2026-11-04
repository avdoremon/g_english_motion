import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/app/game_controller.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/modes/drag_spell.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/session/level_session.dart';

import '../helpers/game_harness.dart';
import '../helpers/synthetic_poses.dart';

void main() {
  late GameHarness h;

  setUp(() async {
    h = await GameHarness.create(grade: 3, modes: const [ModeKind.dragSpell]);
    await h.startAndCalibrate();
  });

  tearDown(() => h.dispose());

  test('grade 3 is planned with DragSpell questions and rounds', () {
    final s = h.controller.session!;
    expect(h.controller.phase, GamePhase.playing);
    for (final pq in s.plan) {
      expect(pq.mode, ModeKind.dragSpell);
      expect(pq.question, anyOf(isA<SpellQuestion>(), isA<OrderQuestion>()));
    }
    expect(s.round, isA<DragSpellRound>());
    // base 20 s + 3 s per slot
    final slots = (s.round as DragSpellRound).tiles.length;
    expect(s.round.timeLimit, Duration(seconds: 20 + 3 * slots));
  });

  test('a raised wrist reaches the screens as CursorMoved', () async {
    final cursors = <CursorMoved>[];
    h.controller.events.listen((e) {
      if (e is CursorMoved) cursors.add(e);
    });
    await h.run(
      const Duration(milliseconds: 600),
      pose: (_) => makePose(
        hipX: GameHarness.hipXForLane(1, 3),
        rightWrist: const Offset(0.5, 0.4),
      ),
    );
    expect(cursors, isNotEmpty);
    expect(cursors.last.x, inInclusiveRange(0.0, 1.0));
    expect(cursors.last.y, inInclusiveRange(0.0, 1.0));
  });

  test('lane modes do not get cursor events', () async {
    final lane = await GameHarness.create();
    await lane.startAndCalibrate();
    final cursors = <CursorMoved>[];
    lane.controller.events.listen((e) {
      if (e is CursorMoved) cursors.add(e);
    });
    await lane.run(
      const Duration(milliseconds: 600),
      pose: (_) => makePose(
        hipX: GameHarness.hipXForLane(1, 3),
        rightWrist: const Offset(0.5, 0.4),
      ),
    );
    expect(cursors, isEmpty);
    await lane.dispose();
  });

  test('a wrong answer is explained: the right word is read out', () async {
    final s = h.controller.session!;
    final q = s.current.question;
    final r = s.round as DragSpellRound;
    // Fill the slots in tray order: wrong (tiles are scrambled).
    for (var i = 0; i < r.tiles.length; i++) {
      h.controller.holdTarget('tile:$i');
      h.controller.holdTarget('slot:$i');
    }
    h.ttsLog.clear();
    h.controller.holdTarget('check');
    expect(s.phase, SessionPhase.feedback);
    expect(s.lastResult, RoundResult.wrong);
    await pumpEventQueue(times: 20);
    final spoken = q is SpellQuestion
        ? q.word
        : (q as OrderQuestion).answer.join(' ');
    expect(h.ttsLog, contains('tts:$spoken'));
  });

  test(
    'the spoken word / sentence is not shown as a caption before the answer',
    () {
      final q = h.controller.session!.current.question;
      expect(h.controller.shouldShowCaption(q.ttsText), isFalse);
    },
  );
}
