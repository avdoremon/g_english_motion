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

  group('wrong-item cap is hard', () {
    // 12 items, 7 of them wrong, n = 8: floor(0.3 * 8) = 2 wrong questions.
    final r = ContentRepository([_unit(3, 2, 12)]);
    final wrong = [for (var i = 0; i < 7; i++) 'g3u2i$i'];

    Future<List<PlannedQuestion>> planFor(int seed) async {
      final h = InMemoryHistoryStore();
      for (final w in wrong) {
        await h.markWrong(w);
      }
      return _gen(r, history: h, seed: seed).plan(
        level: _level(count: 8, window: UnitWindow.current),
        pos: _pos3,
        modes: {ModeKind.laneJump},
      );
    }

    test(
      'at most floor(0.3 n) wrong questions, still not at index 0',
      () async {
        for (var s = 0; s < 60; s++) {
          final plan = await planFor(s);
          final ids = plan.map((p) => p.question.itemId).toList();
          expect(plan, hasLength(8));
          expect(ids.where(wrong.contains).length, 2, reason: 'seed $s');
          expect(wrong.contains(ids.first), isFalse, reason: 'seed $s');
          var run = 1;
          for (var i = 1; i < plan.length; i++) {
            final a = plan[i - 1].question, b = plan[i].question;
            run =
                (a is ChoiceQuestion &&
                    b is ChoiceQuestion &&
                    a.correctIndex == b.correctIndex)
                ? run + 1
                : 1;
            expect(run, lessThan(3), reason: 'seed $s');
          }
        }
      },
    );

    test('is deterministic for a seed', () async {
      for (final s in [1, 7, 23]) {
        final a = await planFor(s), b = await planFor(s);
        expect(
          [for (final p in a) (p.question.itemId, p.question.form)],
          [for (final p in b) (p.question.itemId, p.question.form)],
        );
      }
    });

    test('when every non-wrong question is used up, wrong items fill the '
        'rest (documented exception)', () async {
      // 2 non-wrong items x 3 forms = 6 non-wrong pairs, n = 10.
      final small = ContentRepository([_unit(3, 2, 6)]);
      final h = InMemoryHistoryStore();
      for (final w in ['g3u2i0', 'g3u2i1', 'g3u2i2', 'g3u2i3']) {
        await h.markWrong(w);
      }
      final plan = _gen(small, history: h).plan(
        level: _level(count: 10, window: UnitWindow.current),
        pos: _pos3,
        modes: {ModeKind.laneJump},
      );
      expect(plan, hasLength(10));
      final nonWrong = plan
          .where(
            (p) =>
                p.question.itemId == 'g3u2i4' || p.question.itemId == 'g3u2i5',
          )
          .length;
      expect(nonWrong, 6, reason: 'all non-wrong pairs used first');
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

  group('determinism and purity', () {
    String describe(PlannedQuestion p) {
      final q = p.question;
      return switch (q) {
        ChoiceQuestion() =>
          '${p.mode.name}|${q.form.name}|${q.itemId}|${q.promptText}|'
              '${q.choices.map((c) => c.itemId).join(",")}|${q.correctIndex}',
        SpellQuestion() => '${p.mode.name}|spell|${q.itemId}|${q.tiles.join()}',
        OrderQuestion() =>
          '${p.mode.name}|order|${q.itemId}|${q.words.join(" ")}',
      };
    }

    test('the same seed gives the same plan', () {
      for (final modes in [
        {ModeKind.laneJump},
        {ModeKind.laneJump, ModeKind.dragSpell, ModeKind.skyShoot},
      ]) {
        for (var s = 0; s < 10; s++) {
          List<String> once() => [
            for (final p in _gen(
              repo,
              seed: s,
            ).plan(level: _level(), pos: _pos3, modes: modes))
              describe(p),
          ];
          expect(once(), once(), reason: 'seed $s $modes');
        }
      }
    });

    test('different seeds give different plans', () {
      List<String> at(int s) => [
        for (final p in _gen(
          repo,
          seed: s,
        ).plan(level: _level(), pos: _pos3, modes: {ModeKind.laneJump}))
          describe(p),
      ];
      expect(
        {for (var s = 0; s < 10; s++) at(s).join(';')}.length,
        greaterThan(5),
      );
    });

    test('plan() does not mutate the history', () async {
      final h = InMemoryHistoryStore();
      await h.recordAsked(['g3u1i1', 'g3u1i2', 'g3u2i0']);
      await h.markWrong('g3u1i3');
      final g = _gen(repo, history: h);
      for (var n = 0; n < 5; n++) {
        g.plan(level: _level(), pos: _pos3, modes: {ModeKind.laneJump});
      }
      expect(h.recentIds(), ['g3u1i1', 'g3u1i2', 'g3u2i0']);
      expect(h.wrongIds(), {'g3u1i3'});
    });
  });

  group('question content', () {
    test('fillBlank: promptText has ____ and ttsText says "blank"', () {
      var seen = 0;
      for (var s = 0; s < 20; s++) {
        final plan = _gen(
          repo,
          seed: s,
        ).plan(level: _level(), pos: _pos3, modes: {ModeKind.skyShoot});
        for (final p in plan) {
          final q = p.question;
          if (q is! ChoiceQuestion || q.form != QuestionForm.fillBlank) {
            continue;
          }
          seen++;
          final word = repo.byId(q.itemId).word;
          expect(q.promptText, contains('____'));
          expect(q.promptText, isNot(contains(word)));
          expect(q.ttsText, contains('blank'));
          expect(q.ttsText, isNot(contains('____')));
          expect(q.ttsText, isNot(contains(word)));
        }
      }
      expect(seen, greaterThan(0));
    });

    test('fillBlank never leaves the word in the prompt or the tts', () {
      // "The orange is orange": blanking only the first occurrence shows and
      // speaks the answer.
      final twice = ContentRepository([
        Unit(
          grade: 3,
          index: 1,
          id: 'u01',
          title: 'g3u1',
          items: [
            for (var i = 0; i < 6; i++)
              ContentItem(
                id: 'twice$i',
                word: 'orange$i',
                ttsText: 'orange$i',
                sentencePatterns: [
                  'The orange$i is orange$i',
                  'I like orange$i',
                ],
                distractorIds: ['twice${(i + 1) % 6}', 'twice${(i + 2) % 6}'],
                modes: const [ModeKind.skyShoot],
              ),
          ],
        ),
      ]);
      var seen = 0;
      for (var s = 0; s < 30; s++) {
        final plan = _gen(twice, seed: s).plan(
          level: _level(choices: 3),
          pos: const CurriculumPosition(grade: 3, currentUnitIndex: 1),
          modes: {ModeKind.skyShoot},
        );
        for (final p in plan) {
          final q = p.question;
          if (q is! ChoiceQuestion || q.form != QuestionForm.fillBlank) {
            continue;
          }
          seen++;
          final word = twice.byId(q.itemId).word;
          expect(q.promptText, isNot(contains(word)), reason: 'seed $s');
          expect(q.ttsText, isNot(contains(word)), reason: 'seed $s');
        }
      }
      expect(seen, greaterThan(0));
    });

    test('an item whose every pattern repeats the word is not fillBlank', () {
      final repeats = ContentRepository([
        Unit(
          grade: 3,
          index: 1,
          id: 'u01',
          title: 'g3u1',
          items: [
            for (var i = 0; i < 6; i++)
              ContentItem(
                id: 'bye$i',
                word: 'bye$i',
                ttsText: 'bye$i',
                sentencePatterns: ['Bye$i bye$i my friend'],
                distractorIds: ['bye${(i + 1) % 6}', 'bye${(i + 2) % 6}'],
                modes: const [ModeKind.skyShoot],
              ),
          ],
        ),
      ]);
      for (var s = 0; s < 20; s++) {
        final plan = _gen(repeats, seed: s).plan(
          level: _level(choices: 3),
          pos: const CurriculumPosition(grade: 3, currentUnitIndex: 1),
          modes: {ModeKind.skyShoot},
        );
        expect(plan, isNotEmpty);
        for (final p in plan) {
          expect(
            p.question.form,
            isNot(QuestionForm.fillBlank),
            reason: 'seed $s',
          );
        }
      }
    });

    test('OrderQuestion.answer equals the (normalised) sentence', () {
      var seen = 0;
      for (var s = 0; s < 20; s++) {
        final plan = _gen(
          repo,
          seed: s,
        ).plan(level: _level(), pos: _pos3, modes: {ModeKind.dragSpell});
        for (final p in plan) {
          final q = p.question;
          if (q is! OrderQuestion) continue;
          seen++;
          final sentences = repo
              .byId(q.itemId)
              .sentencePatterns
              .map((x) => x.trim().split(RegExp(r'\s+')).join(' '));
          expect(sentences, contains(q.answer.join(' ')));
          expect(q.ttsText.trim().split(RegExp(r'\s+')), q.answer);
        }
      }
      expect(seen, greaterThan(0));
    });

    ContentItem word(String w, {List<String> sentences = const []}) =>
        ContentItem(
          id: 'w-$w'.replaceAll(RegExp(r'[^a-z0-9-]'), '_'),
          word: w,
          ttsText: w,
          sentencePatterns: sentences,
          modes: const [ModeKind.dragSpell, ModeKind.skyShoot],
        );

    Unit unitOf(List<ContentItem> items) =>
        Unit(grade: 3, index: 1, id: 'u01', title: 't', items: items);

    Set<QuestionForm> formsFor(
      List<ContentItem> items,
      ModeKind mode, {
      int n = 20,
    }) {
      final r = ContentRepository([unitOf(items)]);
      final forms = <QuestionForm>{};
      for (var s = 0; s < 10; s++) {
        final plan = _gen(r, seed: s).plan(
          level: _level(count: n, window: UnitWindow.current),
          pos: const CurriculumPosition(grade: 3, currentUnitIndex: 1),
          modes: {mode},
        );
        for (final p in plan) {
          forms.add(p.question.form);
        }
      }
      return forms;
    }

    test(
      'spell eligibility edges: length 2 and identical letters excluded',
      () {
        bool spells(String w) => formsFor([
          word(w),
        ], ModeKind.dragSpell).contains(QuestionForm.spellWord);
        expect(spells('at'), isFalse); // length 2
        expect(spells('aaa'), isFalse); // identical letters
        expect(spells('aab'), isTrue); // length 3, two distinct letters
        expect(spells('cat'), isTrue);
      },
    );

    test('spellWord skips words with spaces and non-letters', () {
      for (final w in ['ice cream', 'T-shirt', "don't", 'a.b.c', 'tv2']) {
        expect(
          formsFor([word(w)], ModeKind.dragSpell),
          isNot(contains(QuestionForm.spellWord)),
          reason: w,
        );
      }
      expect(
        formsFor([word('café')], ModeKind.dragSpell),
        contains(QuestionForm.spellWord),
      );
    });

    test('items lacking the mode are excluded from plan()', () {
      final items = [
        for (var i = 0; i < 6; i++)
          ContentItem(
            id: 'lj$i',
            word: 'lj$i',
            ttsText: 'lj$i',
            modes: const [ModeKind.laneJump],
          ),
        for (var i = 0; i < 6; i++)
          ContentItem(
            id: 'ds$i',
            word: 'ds$i',
            ttsText: 'ds$i',
            modes: const [ModeKind.dragSpell],
          ),
      ];
      final r = ContentRepository([
        Unit(grade: 1, index: 1, id: 'u01', title: 't', items: items),
      ]);
      for (var s = 0; s < 10; s++) {
        final plan = _gen(r, seed: s).plan(
          level: _level(count: 6),
          pos: const CurriculumPosition(grade: 1, currentUnitIndex: 1),
          modes: {ModeKind.laneJump},
        );
        expect(plan, hasLength(6));
        for (final p in plan) {
          expect(p.question.itemId, startsWith('lj'));
        }
      }
    });

    test('fillBlank uses a Unicode-safe, escaped word-boundary match', () {
      final items = [
        word('ice cream', sentences: ['I like ice cream a lot.']),
        word('café', sentences: ['We eat at the café today.']),
        word('t-shirt', sentences: ['My t-shirt is red.']),
        word('a.b', sentences: ['Say a.b now, not axb.']),
        // Substring of a longer word must not match.
        word('cat', sentences: ['The cats sleep.']),
        word('hat', sentences: ['My hat is big.']),
        word('dog', sentences: ['The dog runs fast.']),
      ];
      final r = ContentRepository([unitOf(items)]);
      final blanks = <String, String>{};
      for (var s = 0; s < 30; s++) {
        final plan = _gen(r, seed: s).plan(
          level: _level(count: 12, window: UnitWindow.current),
          pos: const CurriculumPosition(grade: 3, currentUnitIndex: 1),
          modes: {ModeKind.skyShoot},
        );
        for (final p in plan) {
          final q = p.question;
          if (q is ChoiceQuestion && q.form == QuestionForm.fillBlank) {
            blanks[r.byId(q.itemId).word] = q.promptText!;
          }
        }
      }
      expect(blanks['ice cream'], 'I like ____ a lot.');
      expect(blanks['café'], 'We eat at the ____ today.');
      expect(blanks['t-shirt'], 'My ____ is red.');
      expect(blanks['a.b'], 'Say ____ now, not axb.');
      expect(blanks['hat'], 'My ____ is big.');
      expect(blanks.containsKey('cat'), isFalse); // "cats" is not "cat"
    });
  });

  group('item diversity', () {
    ContentRepository pool(int items) => ContentRepository([
      _unit(1, 1, items, modes: const [ModeKind.laneJump]),
    ]);
    const pos = CurriculumPosition(grade: 1, currentUnitIndex: 1);

    test('12 items x 3 forms, 8 questions -> 8 distinct items', () {
      final r = pool(12);
      for (var s = 0; s < 50; s++) {
        final plan = _gen(r, seed: s).plan(
          level: _level(count: 8, window: UnitWindow.current),
          pos: pos,
          modes: {ModeKind.laneJump},
        );
        expect(plan, hasLength(8));
        expect(
          {for (final p in plan) p.question.itemId},
          hasLength(8),
          reason: 'seed $s',
        );
      }
    });

    test('all items are used once before any repeats (n > items)', () {
      final r = pool(5);
      for (var s = 0; s < 30; s++) {
        final plan = _gen(r, seed: s).plan(
          level: _level(count: 8, window: UnitWindow.current),
          pos: pos,
          modes: {ModeKind.laneJump},
        );
        final counts = <String, int>{};
        for (final p in plan) {
          counts.update(p.question.itemId, (c) => c + 1, ifAbsent: () => 1);
        }
        expect(counts, hasLength(5), reason: 'seed $s');
        expect(counts.values.where((c) => c > 2), isEmpty, reason: 'seed $s');
        // (itemId, form) pairs are still unique while the pool allows.
        expect(_keys(plan), hasLength(8), reason: 'seed $s');
      }
    });

    test(
      'fresh items beat recently asked ones in the item-first pass',
      () async {
        final r = pool(12);
        final h = InMemoryHistoryStore();
        final recent = [for (var i = 0; i < 6; i++) 'g1u1i$i'];
        await h.recordAsked(recent);
        for (var s = 0; s < 30; s++) {
          final plan = _gen(r, history: h, seed: s).plan(
            level: _level(count: 6, window: UnitWindow.current),
            pos: pos,
            modes: {ModeKind.laneJump},
          );
          expect(
            plan
                .map((p) => p.question.itemId)
                .toSet()
                .intersection(recent.toSet()),
            isEmpty,
            reason: 'seed $s',
          );
        }
      },
    );

    test('no adjacent plan entries share an item when the pool allows', () {
      final r = pool(4);
      for (var s = 0; s < 50; s++) {
        final plan = _gen(r, seed: s).plan(
          level: _level(count: 10, window: UnitWindow.current),
          pos: pos,
          modes: {ModeKind.laneJump},
        );
        for (var i = 1; i < plan.length; i++) {
          expect(
            plan[i].question.itemId,
            isNot(plan[i - 1].question.itemId),
            reason: 'seed $s index $i',
          );
        }
      }
    });
  });

  group('wrong ids outside the level window', () {
    test('are ignored: never planned and no effect on the quota', () async {
      final h = InMemoryHistoryStore();
      // Window = unit 2 only; wrong ids live in unit 1 and in another grade.
      for (final w in ['g3u1i0', 'g3u1i1', 'g1u1i0', 'unknown-id']) {
        await h.markWrong(w);
      }
      for (var s = 0; s < 20; s++) {
        final plan = _gen(repo, history: h, seed: s).plan(
          level: _level(count: 8, window: UnitWindow.current),
          pos: _pos3,
          modes: {ModeKind.laneJump},
        );
        expect(plan, hasLength(8));
        for (final p in plan) {
          expect(p.question.itemId, startsWith('g3u2'));
        }
      }
    });
  });
}
