import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/speech/word_judge.dart';

ContentItem item(String word, {List<String> variants = const []}) =>
    ContentItem(
      id: 'x-$word',
      word: word,
      ttsText: word,
      spokenVariants: variants,
      modes: const [ModeKind.sayIt],
    );

RecognitionResult r(List<String> t, {List<double>? c, int id = 1}) =>
    RecognitionResult(transcripts: t, confidences: c, sessionId: id);

void main() {
  group('normalize', () {
    test('lowercases, strips punctuation', () {
      expect(WordJudge.normalize('  The Hand!! '), 'hand');
    });
    test('hyphen becomes a space', () {
      expect(WordJudge.normalize('T-shirt'), 't shirt');
    });
    test('digits become words (0-100)', () {
      expect(WordJudge.normalize('8'), 'eight');
      expect(WordJudge.normalize('0'), 'zero');
      expect(WordJudge.normalize('21'), 'twenty one');
      expect(WordJudge.normalize('100'), 'one hundred');
      expect(WordJudge.normalize('101'), '101');
    });
    test('leading article dropped, only when something remains', () {
      expect(WordJudge.normalize('a cat'), 'cat');
      expect(WordJudge.normalize('An apple'), 'apple');
      expect(WordJudge.normalize('the'), 'the');
    });
    test('apostrophes vanish, whitespace collapses', () {
      expect(WordJudge.normalize("it's   ok"), 'its ok');
    });
  });

  group('matches', () {
    final hand = item('hand');
    test('matches at the third alternative', () {
      expect(WordJudge.matches(r(['hat', 'ham', 'Hand']), hand), isTrue);
    });
    test('matches a spokenVariant', () {
      final tShirt = item('T-shirt', variants: ['tee shirt']);
      expect(WordJudge.matches(r(['Tee shirt']), tShirt), isTrue);
      expect(WordJudge.matches(r(['t-shirt']), tShirt), isTrue);
    });
    test('spoken digit matches a number word', () {
      expect(WordJudge.matches(r(['8']), item('eight')), isTrue);
    });
    test('wrong word, empty list, extra words are not a match', () {
      expect(WordJudge.matches(r(['hat']), hand), isFalse);
      expect(WordJudge.matches(r([]), hand), isFalse);
      expect(WordJudge.matches(r(['a hand please']), hand), isFalse);
    });
    test('low confidence on the matching alternative does not match', () {
      expect(WordJudge.matches(r(['hand'], c: [0.1]), hand), isFalse);
      expect(WordJudge.matches(r(['hand'], c: [0.3]), hand), isTrue);
    });
    test('confidence <= 0 means unknown and is ignored', () {
      expect(
        WordJudge.matches(r(['x', 'y', 'hand'], c: [0.9, 0.0, -1]), hand),
        isTrue,
      );
      expect(WordJudge.matches(r(['hand'], c: [0.0]), hand), isTrue);
    });
    test('missing confidences entries are ignored', () {
      expect(WordJudge.matches(r(['x', 'hand'], c: [0.9]), hand), isTrue);
    });
  });

  group('judge (uncertain is never a miss)', () {
    final hand = item('hand');
    test('empty or blank transcripts are uncertain', () {
      expect(WordJudge.judge(r([]), hand), Judgement.uncertain);
      expect(WordJudge.judge(r(['', '  ']), hand), Judgement.uncertain);
    });
    test('only low-confidence alternatives are uncertain', () {
      expect(
        WordJudge.judge(r(['hat', 'hand'], c: [0.1, 0.2]), hand),
        Judgement.uncertain,
      );
    });
    test('a confident or unscored different word is a miss', () {
      expect(WordJudge.judge(r(['hat']), hand), Judgement.miss);
      expect(WordJudge.judge(r(['hat'], c: [0.8]), hand), Judgement.miss);
      expect(WordJudge.judge(r(['hat'], c: [0.0]), hand), Judgement.miss);
    });
    test('a match wins', () {
      expect(WordJudge.judge(r(['hand']), hand), Judgement.match);
    });
  });
}
