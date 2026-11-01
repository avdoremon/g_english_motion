import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/content/content_repository.dart';
import 'package:g_english_motion/content/history_store.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_generator.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/levels/level_config.dart';

const _allModes = [
  ModeKind.laneJump,
  ModeKind.dragSpell,
  ModeKind.skyShoot,
  ModeKind.sayIt,
];

Unit _unit(
  int grade,
  int index,
  int count, {
  bool images = true,
  List<ModeKind> modes = _allModes,
  int Function(int i)? syllables,
}) {
  final p = 'g${grade}u$index';
  return Unit(
    grade: grade,
    index: index,
    id: 'u${index.toString().padLeft(2, '0')}',
    title: p,
    items: [
      for (var i = 0; i < count; i++)
        ContentItem(
          id: '${p}i$i',
          word: 'x$index${i}y',
          ttsText: 'x$index${i}y',
          image: images ? 'assets/$p$i.png' : null,
          syllables: syllables?.call(i) ?? 1,
          sentencePatterns: [
            'I like x$index${i}y a lot',
            'We see x$index${i}y',
          ],
          distractorIds: ['${p}i${(i + 1) % count}', '${p}i${(i + 2) % count}'],
          modes: modes,
        ),
    ],
  );
}

LevelConfig _level({
  int count = 10,
  int choices = 4,
  UnitWindow window = UnitWindow.currentPlus1,
}) => LevelConfig(
  level: 1,
  questionCount: count,
  baseTime: const Duration(seconds: 5),
  choiceCount: choices,
  hints: HintMode.full,
  window: window,
);

const _pos3 = CurriculumPosition(grade: 3, currentUnitIndex: 2);
const _pos1 = CurriculumPosition(grade: 1, currentUnitIndex: 2);

QuestionGenerator _gen(
  ContentRepository repo, {
  HistoryStore? history,
  int seed = 42,
}) => QuestionGenerator(repo, history ?? InMemoryHistoryStore(), Random(seed));

Set<(String, QuestionForm)> _keys(List<PlannedQuestion> q) => {
  for (final p in q) (p.question.itemId, p.question.form),
};

void main() {
  final repo = ContentRepository([
    _unit(3, 1, 10),
    _unit(3, 2, 10),
    _unit(1, 1, 10, syllables: (i) => i % 4 == 3 ? 3 : 1 + i % 2),
    _unit(1, 2, 10),
  ]);

  test('(a) no duplicate (itemId, form) in a plan when the pool is large', () {
    for (var s = 0; s < 20; s++) {
      final plan = _gen(
        repo,
        seed: s,
      ).plan(level: _level(), pos: _pos3, modes: {ModeKind.laneJump});
      expect(plan, hasLength(10));
      expect(_keys(plan), hasLength(10));
    }
  });

  test(
    '(b) correctIndex never repeats three times in a row over 200 plans',
    () {
      final g = _gen(repo);
      for (var n = 0; n < 200; n++) {
        final plan = g.plan(
          level: _level(),
          pos: _pos3,
          modes: {ModeKind.laneJump, ModeKind.skyShoot},
        );
        final idx = [
          for (final p in plan)
            if (p.question case ChoiceQuestion(:final correctIndex))
              correctIndex,
        ];
        for (var i = 2; i < idx.length; i++) {
          expect(
            idx[i] == idx[i - 1] && idx[i] == idx[i - 2],
            isFalse,
            reason: 'plan $n: $idx',
          );
        }
      }
    },
  );

  test(
    '(c) second plan differs from first by >= 70% when pool = 2x count',
    () async {
      final r = ContentRepository([_unit(3, 2, 20, images: false)]);
      final h = InMemoryHistoryStore();
      final g = _gen(r, history: h);
      final level = _level(window: UnitWindow.current);
      final first = g.plan(
        level: level,
        pos: _pos3,
        modes: {ModeKind.laneJump},
      );
      await h.recordAsked([for (final p in first) p.question.itemId]);
      final second = g.plan(
        level: level,
        pos: _pos3,
        modes: {ModeKind.laneJump},
      );
      final k1 = _keys(first);
      final different = _keys(second).where((k) => !k1.contains(k)).length;
      expect(different / second.length, greaterThanOrEqualTo(0.7));
    },
  );

  test('(d) small pool still yields questionCount, repeating only after the pool is used', () {
    final r = ContentRepository([_unit(3, 2, 4, images: false)]);
    final plan = _gen(r).plan(
      level: _level(window: UnitWindow.current),
      pos: _pos3,
      modes: {ModeKind.laneJump},
    );
    expect(plan, hasLength(10));
    expect(_keys(plan.take(4).toList()), hasLength(4));
    expect(_keys(plan.take(8).toList()), hasLength(4));
    final counts = <String, int>{};
    for (final p in plan) {
      counts.update(p.question.itemId, (c) => c + 1, ifAbsent: () => 1);
    }
    expect(counts.values.toSet().difference({2, 3}), isEmpty);
    for (var i = 1; i < plan.length; i++) {
      expect(plan[i].question.itemId, isNot(plan[i - 1].question.itemId));
    }
  });

  test('(e) choices: exact count, no correct duplicate, distractorIds first then window', () {
    final plan = _gen(repo).plan(
      level: _level(window: UnitWindow.current),
      pos: _pos3,
      modes: {ModeKind.laneJump, ModeKind.skyShoot},
    );
    var checked = 0;
    for (final p in plan) {
      final q = p.question;
      if (q is! ChoiceQuestion) continue;
      checked++;
      expect(q.choices, hasLength(4));
      final ids = q.choices.map((c) => c.itemId).toList();
      expect(ids.toSet(), hasLength(4));
      expect(ids[q.correctIndex], q.itemId);
      final item = repo.byId(q.itemId);
      for (final d in item.distractorIds) {
        expect(ids, contains(d));
      }
      for (final id in ids) {
        expect(id.startsWith('g3u2'), isTrue, reason: 'window = current unit');
      }
    }
    expect(checked, greaterThan(0));
  });

  test(
    '(e2) top-up falls back to the rest of the grade when window is too small',
    () {
      final r = ContentRepository([_unit(3, 1, 10), _unit(3, 2, 3)]);
      final plan = _gen(r).plan(
        level: _level(window: UnitWindow.current),
        pos: _pos3,
        modes: {ModeKind.laneJump},
      );
      for (final p in plan) {
        final q = p.question as ChoiceQuestion;
        expect(q.choices.map((c) => c.itemId).toSet(), hasLength(4));
      }
    },
  );

  test('(f) spell tiles are a different permutation of the word', () {
    final plan = _gen(repo)
        .plan(level: _level(), pos: _pos3, modes: {ModeKind.dragSpell});
    var spells = 0, orders = 0;
    for (final p in plan) {
      switch (p.question) {
        case SpellQuestion(:final word, :final tiles):
          spells++;
          expect(tiles.join(), isNot(word));
          expect([...tiles]..sort(), [...word.split('')]..sort());
        case OrderQuestion(:final words, :final answer):
          orders++;
          expect(words.join(' '), isNot(answer.join(' ')));
          expect([...words]..sort(), [...answer]..sort());
          expect(answer.length, inInclusiveRange(3, 6));
        case ChoiceQuestion():
          fail('dragSpell must not produce choice questions');
      }
    }
    expect(spells + orders, 10);
  });

  group('wrong ids', () {
    test('(g) 3 wrong items all appear, none at position 0', () async {
      for (var s = 0; s < 30; s++) {
        final h = InMemoryHistoryStore();
        final wrong = ['g3u1i1', 'g3u1i5', 'g3u2i3'];
        for (final w in wrong) {
          await h.markWrong(w);
        }
        final plan = _gen(
          repo,
          history: h,
          seed: s,
        ).plan(level: _level(), pos: _pos3, modes: {ModeKind.laneJump});
        final ids = plan.map((p) => p.question.itemId).toList();
        for (final w in wrong) {
          expect(ids, contains(w), reason: 'seed $s');
        }
        expect(wrong.contains(ids.first), isFalse, reason: 'seed $s');
      }
    });

    test('(g) 6 wrong items: at most 3 present (30%)', () async {
      for (var s = 0; s < 30; s++) {
        final h = InMemoryHistoryStore();
        final wrong = [for (var i = 0; i < 6; i++) 'g3u1i$i'];
        for (final w in wrong) {
          await h.markWrong(w);
        }
        final plan = _gen(
          repo,
          history: h,
          seed: s,
        ).plan(level: _level(), pos: _pos3, modes: {ModeKind.laneJump});
        final ids = plan.map((p) => p.question.itemId).toList();
        final present = wrong.where(ids.contains).length;
        expect(present, inInclusiveRange(1, 3), reason: 'seed $s');
        expect(wrong.contains(ids.first), isFalse);
      }
    });
  });

  test('(h) all three modes appear when requested', () {
    for (var s = 0; s < 30; s++) {
      final plan = _gen(repo, seed: s).plan(
        level: _level(),
        pos: _pos3,
        modes: {ModeKind.laneJump, ModeKind.dragSpell, ModeKind.skyShoot},
      );
      expect(plan, hasLength(10));
      expect(plan.map((p) => p.mode).toSet(), {
        ModeKind.laneJump,
        ModeKind.dragSpell,
        ModeKind.skyShoot,
      });
    }
  });

  test('(i) grade 1 never produces spell/order/fillBlank questions', () {
    for (var s = 0; s < 30; s++) {
      final plan = _gen(repo, seed: s).plan(
        level: _level(),
        pos: _pos1,
        modes: {ModeKind.laneJump, ModeKind.dragSpell, ModeKind.skyShoot},
      );
      expect(plan, isNotEmpty);
      for (final p in plan) {
        expect(p.question, isA<ChoiceQuestion>());
        expect(p.question.form, isNot(QuestionForm.fillBlank));
      }
    }
  });

  test(
    '(j) sayItWords grade 1: sayIt mode, <=2 syllables, honours exclude',
    () {
      final r = ContentRepository([
        _unit(1, 1, 10, modes: [ModeKind.laneJump], syllables: (i) => 1),
        Unit(
          grade: 1,
          index: 2,
          id: 'u02',
          title: 'g1u2',
          items: [
            for (var i = 0; i < 10; i++)
              ContentItem(
                id: 'say$i',
                word: 'say$i',
                ttsText: 'say$i',
                syllables: i % 2 == 0 ? 3 : 1 + (i % 2),
                modes: [if (i != 5) ModeKind.sayIt, ModeKind.laneJump],
              ),
          ],
        ),
      ]);
      for (var s = 0; s < 30; s++) {
        final words = _gen(
          r,
          seed: s,
        ).sayItWords(pos: _pos1, level: _level(), count: 3, exclude: {'say1'});
        expect(words, hasLength(3));
        expect(words.map((w) => w.id).toSet(), hasLength(3));
        for (final w in words) {
          expect(w.modes, contains(ModeKind.sayIt));
          expect(w.syllables, lessThanOrEqualTo(2));
          expect(w.id, isNot('say1'));
        }
      }
    },
  );

  test('empty pool yields an empty plan', () {
    final plan = _gen(repo)
        .plan(level: _level(), pos: _pos3, modes: {ModeKind.sayIt});
    expect(plan, isEmpty);
  });

  test(
    'InMemoryHistoryStore keeps the latest 200 ids and tracks wrong ids',
    () async {
      final h = InMemoryHistoryStore();
      await h.recordAsked([for (var i = 0; i < 250; i++) 'a$i']);
      expect(h.recentIds(), hasLength(200));
      expect(h.recentIds().last, 'a249');
      expect(h.recentIds().first, 'a50');
      await h.markWrong('a1');
      expect(h.wrongIds(), {'a1'});
      await h.clearWrong('a1');
      expect(h.wrongIds(), isEmpty);
    },
  );
}
