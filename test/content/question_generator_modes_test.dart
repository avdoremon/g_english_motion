import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/content_repository.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/content/edit_distance.dart';
import 'package:g_english_motion/content/history_store.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_generator.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/levels/level_config.dart';

const _words = [
  'cat',
  'cap',
  'cut',
  'cot',
  'car',
  'bat',
  'bag',
  'big',
  'bug',
  'dog',
  'elephant',
  'umbrella',
];

Unit _unit(int grade, int index, ModeKind mode) {
  final p = 'g${grade}u$index';
  return Unit(
    grade: grade,
    index: index,
    id: 'u${index.toString().padLeft(2, '0')}',
    title: p,
    items: [
      for (var i = 0; i < _words.length; i++)
        ContentItem(
          id: '$p-${_words[i]}',
          word: _words[i],
          ttsText: _words[i],
          image: 'assets/${_words[i]}.png',
          syllables: 1,
          sentencePatterns: ['I see ${_words[i]} here'],
          distractorIds: [
            '$p-${_words[(i + 6) % _words.length]}',
            '$p-${_words[(i + 7) % _words.length]}',
          ],
          modes: [mode],
        ),
    ],
  );
}

LevelConfig _level({int choices = 4, int count = 10}) => LevelConfig(
  level: 1,
  questionCount: count,
  baseTime: const Duration(seconds: 5),
  choiceCount: choices,
  hints: HintMode.full,
  window: UnitWindow.current,
);

List<PlannedQuestion> _plan(
  ModeKind mode, {
  int choices = 4,
  int seed = 1,
  int grade = 3,
}) {
  final repo = ContentRepository([
    _unit(grade, 1, mode),
    _unit(grade, 2, mode),
  ]);
  return QuestionGenerator(repo, InMemoryHistoryStore(), Random(seed)).plan(
    level: _level(choices: choices),
    pos: CurriculumPosition(grade: grade, currentUnitIndex: 2),
    modes: {mode},
  );
}

String _wordOf(ChoiceQuestion q, int i) {
  final id = q.choices[i].itemId;
  return id.substring(id.indexOf('-') + 1);
}

void main() {
  test('editDistance matches the Python tool (shared sample)', () {
    // Keep in step with test/tools/test_tag_modes.py (test_lev_parity).
    const sample = [
      ('cat', 'cap', 1),
      ('', 'abc', 3),
      ('kitten', 'sitting', 3),
      ('flaw', 'lawn', 2),
      ('intention', 'execution', 5),
      ('same', 'same', 0),
      ('book', 'back', 2),
    ];
    for (final (a, b, d) in sample) {
      expect(editDistance(a, b), d, reason: '$a/$b');
      expect(editDistance(b, a), d, reason: '$b/$a');
    }
  });

  test('laneJump still gets level.choiceCount choices', () {
    for (final choices in [3, 4]) {
      final plan = _plan(ModeKind.laneJump, choices: choices, grade: 1);
      expect(plan, isNotEmpty);
      for (final pq in plan) {
        expect((pq.question as ChoiceQuestion).choices, hasLength(choices));
      }
    }
  });

  test('editDistance', () {
    expect(editDistance('cat', 'cap'), 1);
    expect(editDistance('', 'abc'), 3);
    expect(editDistance('kitten', 'sitting'), 3);
    expect(editDistance('Cat', 'cat'), 0, reason: 'case-insensitive');
  });

  group('popWord', () {
    test('3-5 balloons, all within edit distance 2, no duplicates', () {
      for (final choices in [2, 3, 4, 5, 8]) {
        for (var seed = 0; seed < 10; seed++) {
          final plan = _plan(ModeKind.balloonPop, choices: choices, seed: seed);
          expect(plan, isNotEmpty);
          for (final pq in plan) {
            expect(pq.mode, ModeKind.balloonPop);
            final q = pq.question as ChoiceQuestion;
            expect(q.form, QuestionForm.popWord);
            expect(q.choices.length, inInclusiveRange(3, 5));
            expect(q.correctIndex, inInclusiveRange(0, q.choices.length - 1));
            expect(q.choices[q.correctIndex].itemId, q.itemId);
            expect(q.promptImageItemId, q.itemId);
            expect(q.ttsText, _wordOf(q, q.correctIndex));
            final answer = _wordOf(q, q.correctIndex);
            final seen = <String>{};
            for (var i = 0; i < q.choices.length; i++) {
              final w = _wordOf(q, i);
              expect(seen.add(w), isTrue, reason: 'duplicate $w');
              expect(q.choices[i].showWord, isTrue);
              expect(q.choices[i].showPicture, isFalse);
              if (i != q.correctIndex) {
                expect(
                  editDistance(w, answer),
                  lessThanOrEqualTo(2),
                  reason: '$w vs $answer',
                );
              }
            }
          }
        }
      }
    });

    test('items without two near words are never asked', () {
      final plan = _plan(ModeKind.balloonPop);
      for (final pq in plan) {
        expect(pq.question.itemId, isNot(endsWith('elephant')));
        expect(pq.question.itemId, isNot(endsWith('umbrella')));
      }
    });
  });

  group('memoryMatch', () {
    test('picture prompt, 3-5 word choices, tts = word', () {
      for (final choices in [2, 3, 4, 5, 8]) {
        final plan = _plan(ModeKind.memoryFlip, choices: choices, grade: 2);
        expect(plan, isNotEmpty);
        for (final pq in plan) {
          expect(pq.mode, ModeKind.memoryFlip);
          final q = pq.question as ChoiceQuestion;
          expect(q.form, QuestionForm.memoryMatch);
          expect(q.promptImageItemId, q.itemId);
          expect(q.promptText, isNull, reason: 'word must not be shown');
          expect(q.choices.length, inInclusiveRange(3, 5));
          expect(q.choices[q.correctIndex].itemId, q.itemId);
          expect(q.ttsText, _wordOf(q, q.correctIndex));
          expect(
            {for (var i = 0; i < q.choices.length; i++) _wordOf(q, i)}.length,
            q.choices.length,
          );
          for (final c in q.choices) {
            expect(c.showWord, isTrue);
            expect(c.showPicture, isFalse);
          }
        }
      }
    });
  });

  group('catchIt', () {
    test('exactly three picture choices (three lanes)', () {
      for (final choices in [3, 4, 5]) {
        final plan = _plan(ModeKind.catchIt, choices: choices, grade: 1);
        expect(plan, isNotEmpty);
        for (final pq in plan) {
          expect(pq.mode, ModeKind.catchIt);
          final q = pq.question as ChoiceQuestion;
          expect(q.form, QuestionForm.listenPickPicture);
          expect(q.choices, hasLength(3));
          for (final c in q.choices) {
            expect(c.showPicture, isTrue);
            expect(c.showWord, isFalse);
          }
          expect(q.choices[q.correctIndex].itemId, q.itemId);
        }
      }
    });
  });

  group('trueFalse (yesNo)', () {
    const words = [
      'dog',
      'apple',
      'cat',
      'umbrella',
      'book',
      'egg',
      'bag',
      'orange',
      'pen',
      'ice cream',
      'ant',
      'hat',
    ];
    String art(String w) => 'aeiou'.contains(w[0]) ? 'an' : 'a';

    Unit ynUnit(
      int grade,
      int index, {
      bool sentences = true,
      List<String> extraPatterns = const [],
      List<String>? only,
    }) {
      final p = 'g${grade}u$index';
      final ws = only ?? words;
      return Unit(
        grade: grade,
        index: index,
        id: 'u${index.toString().padLeft(2, '0')}',
        title: p,
        items: [
          for (var i = 0; i < ws.length; i++)
            ContentItem(
              id: '$p-${ws[i]}',
              word: ws[i],
              ttsText: ws[i],
              image: 'assets/${ws[i]}.png',
              sentencePatterns: sentences
                  ? ['This is ${art(ws[i])} ${ws[i]}', ...extraPatterns]
                  : const [],
              distractorIds: [
                '$p-${ws[(i + 1) % ws.length]}',
                '$p-${ws[(i + 2) % ws.length]}',
              ],
              modes: const [ModeKind.yesNo],
            ),
        ],
      );
    }

    List<PlannedQuestion> ynPlan(
      ContentRepository repo, {
      int seed = 1,
      int grade = 1,
      int count = 10,
      int unit = 2,
    }) => QuestionGenerator(repo, InMemoryHistoryStore(), Random(seed)).plan(
      level: _level(count: count),
      pos: CurriculumPosition(grade: grade, currentUnitIndex: unit),
      modes: {ModeKind.yesNo},
    );

    ContentRepository repoOf({bool sentences = true, int grade = 1}) =>
        ContentRepository([
          ynUnit(grade, 1, sentences: sentences),
          ynUnit(grade, 2, sentences: sentences),
        ]);

    bool hasWord(String text, String w) => RegExp(
      '(?<![a-z])${RegExp.escape(w)}(?![a-z])',
      caseSensitive: false,
    ).hasMatch(text);

    test('two silent choices, picture prompt, statement as prompt and tts', () {
      final repo = repoOf();
      for (var seed = 0; seed < 10; seed++) {
        final plan = ynPlan(repo, seed: seed);
        expect(plan, hasLength(10));
        for (final pq in plan) {
          expect(pq.mode, ModeKind.yesNo);
          final q = pq.question as ChoiceQuestion;
          expect(q.form, QuestionForm.trueFalse);
          expect(q.choices, hasLength(2));
          for (final c in q.choices) {
            expect(c.itemId, q.itemId);
            expect(c.showPicture, isFalse);
            expect(c.showWord, isFalse);
          }
          expect(q.promptImageItemId, q.itemId);
          expect(q.promptText, isNotNull);
          expect(q.ttsText, q.promptText);
          expect(q.correctIndex, anyOf(0, 1));
        }
      }
    });

    test('true and false statements differ by at most one per plan', () {
      final repo = repoOf();
      for (final count in [1, 2, 7, 8, 10, 11]) {
        for (var seed = 0; seed < 20; seed++) {
          final plan = ynPlan(repo, seed: seed, count: count);
          final trues = plan
              .where((p) => (p.question as ChoiceQuestion).correctIndex == 0)
              .length;
          final falses = plan.length - trues;
          expect(
            (trues - falses).abs(),
            lessThanOrEqualTo(1),
            reason: 'count $count seed $seed',
          );
        }
      }
    });

    test('balance is deterministic per seed and varies across seeds', () {
      final repo = repoOf();
      List<int> order(int seed) => [
        for (final p in ynPlan(repo, seed: seed))
          (p.question as ChoiceQuestion).correctIndex,
      ];
      expect(order(3), order(3));
      expect(
        {for (var s = 0; s < 20; s++) order(s).join()}.length,
        greaterThan(1),
      );
    });

    test(
      'true statement has the item word; false has a distractor, not it',
      () {
        final repo = repoOf();
        var trues = 0, falses = 0;
        for (var seed = 0; seed < 20; seed++) {
          for (final pq in ynPlan(repo, seed: seed)) {
            final q = pq.question as ChoiceQuestion;
            final word = repo.byId(q.itemId).word;
            final text = q.promptText!;
            if (q.correctIndex == 0) {
              trues++;
              expect(hasWord(text, word), isTrue, reason: text);
            } else {
              falses++;
              expect(hasWord(text, word), isFalse, reason: text);
              final own = repo.byId(q.itemId).distractorIds;
              final claimed = [for (final id in own) repo.byId(id).word];
              expect(
                claimed.any((w) => hasWord(text, w)),
                isTrue,
                reason: text,
              );
            }
          }
        }
        expect(trues, greaterThan(0));
        expect(falses, greaterThan(0));
      },
    );

    test('a/an agrees with the swapped word', () {
      final repo = repoOf();
      final bad = RegExp(
        r'\b(a) [aeiou]|\b(an) [^aeiou]',
        caseSensitive: false,
      );
      for (var seed = 0; seed < 30; seed++) {
        for (final pq in ynPlan(repo, seed: seed)) {
          final t = (pq.question as ChoiceQuestion).promptText!;
          expect(bad.hasMatch(t), isFalse, reason: t);
        }
      }
      // Both directions occur: an -> a and a -> an.
      final texts = {
        for (var seed = 0; seed < 30; seed++)
          for (final pq in ynPlan(repo, seed: seed))
            (pq.question as ChoiceQuestion).promptText!,
      };
      expect(texts.any((t) => t.startsWith('This is an ')), isTrue);
      expect(texts.any((t) => t.startsWith('This is a ')), isTrue);
    });

    test('only the swapped word\'s article is fixed', () {
      const ws = ['dog', 'cat', 'bag', 'hat', 'pen', 'book'];
      final repo = ContentRepository([
        ynUnit(1, 1, only: ws, extraPatterns: const []),
        Unit(
          grade: 1,
          index: 2,
          id: 'u02',
          title: 'g1u2',
          items: [
            for (var i = 0; i < ws.length; i++)
              ContentItem(
                id: 'g1u2-${ws[i]}',
                word: ws[i],
                ttsText: ws[i],
                image: 'a.png',
                sentencePatterns: ['A man has a ${ws[i]} and a rug'],
                distractorIds: ['g1u2-${ws[(i + 1) % ws.length]}'],
                modes: const [ModeKind.yesNo],
              ),
          ],
        ),
      ]);
      for (var seed = 0; seed < 20; seed++) {
        for (final pq in ynPlan(repo, seed: seed, unit: 2)) {
          final q = pq.question as ChoiceQuestion;
          if (!q.itemId.startsWith('g1u2')) continue;
          expect(q.promptText, startsWith('A man has a '));
          expect(q.promptText, endsWith(' and a rug'));
        }
      }
    });

    test('an article-less swap and a capitalised word keep their case', () {
      final repo = ContentRepository([
        Unit(
          grade: 1,
          index: 1,
          id: 'u01',
          title: 'g1u1',
          items: [
            for (final (i, w) in ['dog', 'cat', 'bag', 'hat'].indexed)
              ContentItem(
                id: 'g1u1-$w',
                word: w,
                ttsText: w,
                image: 'a.png',
                sentencePatterns: [
                  '${w[0].toUpperCase()}${w.substring(1)} is here',
                ],
                distractorIds: [
                  'g1u1-${['dog', 'cat', 'bag', 'hat'][(i + 1) % 4]}',
                ],
                modes: const [ModeKind.yesNo],
              ),
          ],
        ),
      ]);
      for (var seed = 0; seed < 10; seed++) {
        for (final pq in ynPlan(repo, seed: seed, count: 4, unit: 1)) {
          final t = (pq.question as ChoiceQuestion).promptText!;
          expect(t, matches(RegExp(r'^[A-Z][a-z]+ is here$')), reason: t);
        }
      }
    });

    // A repo whose yesNo items are given as (word, patterns, distractor
    // words); returns the statements of every plan over [seeds] seeds.
    List<({String item, bool isTrue, String text})> statements(
      List<(String, List<String>, List<String>)> defs, {
      int seeds = 25,
    }) {
      String id(String w) => 'g1u1-$w';
      final repo = ContentRepository([
        Unit(
          grade: 1,
          index: 1,
          id: 'u01',
          title: 'g1u1',
          items: [
            for (final (w, pats, ds) in defs)
              ContentItem(
                id: id(w),
                word: w,
                ttsText: w,
                image: 'a.png',
                sentencePatterns: pats,
                distractorIds: [for (final d in ds) id(d)],
                modes: const [ModeKind.yesNo],
              ),
            // Distractor words that are not asked themselves.
            for (final w in {
              for (final d in defs) ...d.$3,
            }.difference({for (final d in defs) d.$1}))
              ContentItem(
                id: id(w),
                word: w,
                ttsText: w,
                image: 'a.png',
                modes: const [ModeKind.laneJump],
              ),
          ],
        ),
      ]);
      return [
        for (var seed = 0; seed < seeds; seed++)
          for (final pq in ynPlan(
            repo,
            seed: seed,
            count: defs.length,
            unit: 1,
          ))
            (
              item: repo.byId(pq.question.itemId).word,
              isTrue: (pq.question as ChoiceQuestion).correctIndex == 0,
              text: (pq.question as ChoiceQuestion).promptText!,
            ),
      ];
    }

    test(
      'an item word repeated in its sentence falls back to the bare word',
      () {
        final out = statements([
          ('orange', ['The orange is orange'], ['green', 'red']),
          ('green', ['The green is green'], ['orange', 'red']),
          ('red', ['Red is red'], ['green', 'orange']),
        ]);
        for (final st in out) {
          if (st.isTrue) {
            expect(st.text, st.item, reason: st.text);
          } else {
            expect(st.text.contains(' '), isFalse, reason: st.text);
            expect(st.text, isNot(st.item));
          }
        }
      },
    );

    test(
      '"Bye bye my friend" and "The desk is on the desk" are not swapped',
      () {
        final out = statements([
          ('bye', ['Bye bye my friend'], ['friend', 'hello']),
          ('desk', ['The desk is on the desk'], ['board', 'chair']),
          ('board', ['The board is beside the board'], ['desk', 'chair']),
          ('library', ['Go library to the library'], ['school', 'park']),
        ]);
        for (final st in out) {
          expect(st.text.split(' '), hasLength(1), reason: st.text);
        }
      },
    );

    test('a claim already in the sentence is skipped, else the bare claim', () {
      // cat: claims are mat (in the sentence) and dog.
      final some = statements([
        ('cat', ['The cat is on the mat'], ['mat', 'dog']),
        ('dog', ['The dog is on the mat'], ['mat', 'cat']),
      ]);
      for (final st in some.where((s) => !s.isTrue)) {
        expect(
          st.text,
          anyOf('The dog is on the mat', 'The cat is on the mat'),
        );
      }
      // Only claim is in the sentence: the bare claimed word.
      final none = statements([
        ('cat', ['A cat is on the mat'], ['mat']),
        ('mat', ['A cat is on the mat'], ['cat']),
      ]);
      for (final st in none.where((s) => !s.isTrue)) {
        expect(st.text, st.item == 'cat' ? 'mat' : 'cat');
      }
    });

    test('a / an is only used with claims the content treats as countable', () {
      final out = statements([
        ('house', ['I live in a house'], ['tennis', 'flat']),
        ('flat', ['I live in a flat'], ['tennis', 'house']),
        ('tennis', ['I play tennis'], ['house']),
      ]);
      for (final st in out.where((s) => !s.isTrue)) {
        expect(st.text, isNot(contains('a tennis')), reason: st.text);
      }
      // The only distractor is not countable: bare word.
      final only = statements([
        ('house', ['I live in a house'], ['tennis']),
        ('tennis', ['I play tennis'], ['house']),
      ]);
      for (final st in only.where((s) => !s.isTrue && s.item == 'house')) {
        expect(st.text, 'tennis');
      }
    });

    test('no usable sentence falls back to the bare claimed word', () {
      final repo = repoOf(sentences: false);
      for (var seed = 0; seed < 10; seed++) {
        for (final pq in ynPlan(repo, seed: seed)) {
          final q = pq.question as ChoiceQuestion;
          final word = repo.byId(q.itemId).word;
          expect(q.promptText, q.ttsText);
          if (q.correctIndex == 0) {
            expect(q.promptText, word);
          } else {
            expect(q.promptText, isNot(word));
            expect(
              repo.byId(q.itemId).distractorIds.map((d) => repo.byId(d).word),
              contains(q.promptText),
            );
          }
        }
      }
    });

    test('a pattern without the item word falls back to the bare word', () {
      final repo = ContentRepository([
        for (final u in [1, 2])
          Unit(
            grade: 1,
            index: u,
            id: 'u0$u',
            title: 'g1u$u',
            items: [
              for (final (i, w) in ['dog', 'cat', 'bag', 'hat'].indexed)
                ContentItem(
                  id: 'g1u$u-$w',
                  word: w,
                  ttsText: w,
                  image: 'a.png',
                  sentencePatterns: const ['Nothing relevant here'],
                  distractorIds: [
                    'g1u$u-${['dog', 'cat', 'bag', 'hat'][(i + 1) % 4]}',
                  ],
                  modes: const [ModeKind.yesNo],
                ),
            ],
          ),
      ]);
      for (final pq in ynPlan(repo, count: 8)) {
        final q = pq.question as ChoiceQuestion;
        expect(q.promptText, isNot(contains('Nothing')));
        expect(q.promptText, q.ttsText);
      }
    });

    test('a distractor containing the item word is never the false claim', () {
      // "ice" appears inside "ice cream": a false claim of "ice cream" would
      // still show the item word "ice".
      final repo = ContentRepository([
        Unit(
          grade: 1,
          index: 1,
          id: 'u01',
          title: 'g1u1',
          items: [
            ContentItem(
              id: 'ice',
              word: 'ice',
              ttsText: 'ice',
              image: 'a.png',
              sentencePatterns: const ['I like ice'],
              distractorIds: const ['icecream', 'dog'],
              modes: const [ModeKind.yesNo],
            ),
            ContentItem(
              id: 'icecream',
              word: 'ice cream',
              ttsText: 'ice cream',
              image: 'a.png',
              sentencePatterns: const ['I like ice cream'],
              distractorIds: const ['dog'],
              modes: const [ModeKind.yesNo],
            ),
            ContentItem(
              id: 'dog',
              word: 'dog',
              ttsText: 'dog',
              image: 'a.png',
              sentencePatterns: const ['I like dog'],
              distractorIds: const ['ice'],
              modes: const [ModeKind.yesNo],
            ),
          ],
        ),
      ]);
      for (var seed = 0; seed < 20; seed++) {
        for (final pq in ynPlan(repo, seed: seed, count: 6, unit: 1)) {
          final q = pq.question as ChoiceQuestion;
          if (q.itemId != 'ice' || q.correctIndex == 0) continue;
          expect(q.promptText, 'I like dog');
        }
      }
    });

    test('item with no image or no usable distractor is never asked', () {
      final repo = ContentRepository([
        Unit(
          grade: 1,
          index: 1,
          id: 'u01',
          title: 'g1u1',
          items: [
            for (final w in ['dog', 'cat', 'bag', 'hat'])
              ContentItem(
                id: w,
                word: w,
                ttsText: w,
                image: w == 'dog' ? null : 'a.png',
                sentencePatterns: ['I see $w'],
                distractorIds: [w == 'cat' ? 'cat' : 'dog'],
                modes: const [ModeKind.yesNo],
              ),
          ],
        ),
      ]);
      for (var seed = 0; seed < 10; seed++) {
        for (final pq in ynPlan(repo, seed: seed, count: 6, unit: 1)) {
          expect(pq.question.itemId, isNot('dog'), reason: 'no image');
        }
      }
    });

    test('no item is asked more than twice (widened pool)', () {
      // Unit 2 alone has 3 items; the pool widens to the whole grade.
      final repo = ContentRepository([
        ynUnit(1, 1),
        ynUnit(1, 2, only: ['dog', 'cat', 'bag']),
      ]);
      for (var seed = 0; seed < 20; seed++) {
        final plan = ynPlan(repo, seed: seed, count: 8);
        expect(plan, hasLength(8));
        final counts = <String, int>{};
        for (final pq in plan) {
          counts.update(pq.question.itemId, (c) => c + 1, ifAbsent: () => 1);
        }
        expect(counts.values.every((c) => c <= 2), isTrue, reason: '$counts');
      }
    });
  });
}
