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
}
