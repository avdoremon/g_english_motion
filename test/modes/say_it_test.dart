import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/modes/say_it.dart';
import 'package:g_english_motion/speech/word_judge.dart';

ContentItem it(String w) => ContentItem(
  id: 'g1-$w',
  word: w,
  ttsText: w,
  modes: const [ModeKind.sayIt],
);

final items = [it('cat'), it('dog'), it('hand')];
const travel = Duration(seconds: 10);

RecognitionResult say(String w, int id, {List<double>? c}) =>
    RecognitionResult(transcripts: [w], confidences: c, sessionId: id);

SayItRound round({bool modelFirst = false, int first = 10, int seed = 1}) =>
    SayItRound(
      items,
      travelTime: travel,
      rng: Random(seed),
      modelFirst: modelFirst,
      firstSessionId: first,
    );

void main() {
  test('constants', () {
    expect(kJudgedHold, const Duration(milliseconds: 700));
    expect(kExplosionTime, const Duration(milliseconds: 800));
    expect(kLateGrace, const Duration(seconds: 1));
  });

  test('exactly three items', () {
    for (final n in [0, 2, 4]) {
      expect(
        () => SayItRound(
          [for (var i = 0; i < n; i++) it('w$i')],
          travelTime: travel,
          rng: Random(1),
          modelFirst: false,
          firstSessionId: 1,
        ),
        throwsArgumentError,
      );
    }
  });

  test('modelFirst waits for the model, then runs', () {
    final r = round(modelFirst: true);
    expect(r.current.phase, WordPhase.waitingForModel);
    r.tick(travel);
    expect(r.current.progress, 0);
    expect(r.current.phase, WordPhase.waitingForModel);
    r.onModelFinished();
    expect(r.current.phase, WordPhase.running);
    r.tick(travel ~/ 2);
    expect(r.current.progress, 0.5);
  });

  test('a recognition while the model plays is dropped', () {
    final r = round(modelFirst: true);
    r.onRecognized(say('cat', 10));
    expect(r.current.phase, WordPhase.waitingForModel);
    expect(r.current.result, isNull);
  });

  test('without modelFirst the word runs at once', () {
    final r = round();
    expect(r.current.phase, WordPhase.running);
    r.tick(travel ~/ 2);
    expect(r.current.progress, 0.5);
  });

  test('match: judged/correct, 700 ms, exploding, 800 ms, gone, next word', () {
    final r = round();
    r.tick(const Duration(seconds: 1));
    r.onRecognized(say('cat', 10));
    expect(r.current.phase, WordPhase.judged);
    expect(r.current.result, RoundResult.correct);
    expect(r.correctCount, 1);
    r.tick(const Duration(milliseconds: 699));
    expect(r.current.phase, WordPhase.judged);
    r.tick(const Duration(milliseconds: 1));
    expect(r.current.phase, WordPhase.exploding);
    r.tick(const Duration(milliseconds: 400));
    expect(r.current.explosionProgress, closeTo(0.5, 1e-9));
    r.tick(const Duration(milliseconds: 400));
    expect(r.current.item.word, 'dog');
    expect(r.current.phase, WordPhase.running);
    expect(r.current.progress, 0);
    expect(r.current.sessionId, 11);
    expect(r.finished, isFalse);
  });

  test('a miss is wrong at once', () {
    final r = round();
    r.onRecognized(say('hat', 10, c: [0.9]));
    expect(r.current.result, RoundResult.wrong);
    expect(r.current.phase, WordPhase.judged);
    expect(r.correctCount, 0);
  });

  test('uncertain recognition never grades: empty or low confidence', () {
    final r = round();
    r.onRecognized(const RecognitionResult(transcripts: [], sessionId: 10));
    r.onRecognized(say('hat', 10, c: [0.1]));
    r.onRecognized(say('', 10));
    expect(r.current.phase, WordPhase.running);
    expect(r.current.result, isNull);
  });

  test('no result: wrong only after the late grace, then explodes', () {
    final r = round();
    r.tick(travel);
    expect(r.current.progress, 1);
    expect(r.current.phase, WordPhase.running);
    r.tick(const Duration(milliseconds: 999));
    expect(r.current.phase, WordPhase.running);
    expect(r.current.result, isNull);
    r.tick(const Duration(milliseconds: 1));
    expect(r.current.phase, WordPhase.judged);
    expect(r.current.result, RoundResult.wrong);
    r.tick(kJudgedHold);
    expect(r.current.phase, WordPhase.exploding);
  });

  test('a late match inside the grace still counts', () {
    final r = round();
    r.tick(travel + const Duration(milliseconds: 900));
    r.onRecognized(say('cat', 10));
    expect(r.current.result, RoundResult.correct);
  });

  test('a late match after the grace is dropped', () {
    final r = round();
    r.tick(travel + kLateGrace);
    r.onRecognized(say('cat', 10));
    expect(r.current.result, RoundResult.wrong);
  });

  test('a big tick walks through the phases', () {
    final r = round();
    r.tick(travel + kLateGrace + kJudgedHold + kExplosionTime);
    expect(r.current.item.word, 'dog');
    expect(r.current.progress, 0);
    expect(r.correctCount, 0);
  });

  test('stale sessionId (previous word) is dropped', () {
    final r = round();
    r.onRecognized(say('cat', 10));
    r.tick(kJudgedHold + kExplosionTime);
    expect(r.current.item.word, 'dog');
    // A late "cat" tagged with the first word's session: must not touch "dog".
    r.onRecognized(say('cat', 10));
    r.onRecognized(say('dog', 10));
    expect(r.current.phase, WordPhase.running);
    expect(r.current.result, isNull);
    r.onRecognized(say('dog', 11));
    expect(r.current.result, RoundResult.correct);
  });

  test('results while judged or exploding are dropped', () {
    final r = round();
    r.onRecognized(say('hat', 10, c: [0.9]));
    r.onRecognized(say('cat', 10));
    expect(r.current.result, RoundResult.wrong);
    r.tick(kJudgedHold);
    r.onRecognized(say('cat', 10));
    expect(r.current.result, RoundResult.wrong);
    expect(r.current.phase, WordPhase.exploding);
  });

  test('three words then finished', () {
    final r = round();
    for (var i = 0; i < 3; i++) {
      expect(r.finished, isFalse);
      r.onRecognized(say(items[i].word, 10 + i));
      r.tick(kJudgedHold + kExplosionTime);
    }
    expect(r.finished, isTrue);
    expect(r.correctCount, 3);
    expect(r.current.phase, WordPhase.gone);
    r.tick(const Duration(seconds: 5));
    r.onRecognized(say('cat', 12));
    expect(r.correctCount, 3);
  });

  test('modelFirst waits for the model for every word', () {
    final r = round(modelFirst: true);
    r.onModelFinished();
    r.onRecognized(say('cat', 10));
    r.tick(kJudgedHold + kExplosionTime);
    expect(r.current.phase, WordPhase.waitingForModel);
    r.onModelFinished();
    expect(r.current.phase, WordPhase.running);
  });

  test('motions: both kinds over 20 rounds with Random(1)', () {
    final rng = Random(1);
    final seen = <WordMotion>{};
    for (var i = 0; i < 20; i++) {
      final r = SayItRound(
        items,
        travelTime: travel,
        rng: rng,
        modelFirst: false,
        firstSessionId: 1,
      );
      for (var k = 0; k < 3; k++) {
        seen.add(r.current.motion);
        r.onRecognized(say(items[k].word, 1 + k));
        r.tick(kJudgedHold + kExplosionTime);
      }
    }
    expect(seen, WordMotion.values.toSet());
  });

  group('SayItLevel', () {
    SayItRound done(int correct) {
      final r = round();
      for (var i = 0; i < 3; i++) {
        r.onRecognized(say(i < correct ? items[i].word : 'zzz', 10 + i));
        r.tick(kJudgedHold + kExplosionTime);
      }
      return r;
    }

    test('8/9 -> 3 stars, 6/9 -> 1 star', () {
      final a = SayItLevel(rounds: [done(3), done(3), done(2)]);
      expect(a.correctOfNine, 8);
      expect(a.stars, 3);
      final b = SayItLevel(rounds: [done(2), done(2), done(2)]);
      expect(b.correctOfNine, 6);
      expect(b.stars, 1);
    });

    test('needs three rounds', () {
      expect(() => SayItLevel(rounds: [done(3)]), throwsArgumentError);
    });

    test('build slices nine words into three rounds with unique sessions', () {
      final nine = [for (var i = 0; i < 9; i++) it('w$i')];
      final l = SayItLevel.build(
        nine,
        travelTime: travel,
        rng: Random(1),
        modelFirst: true,
        firstSessionId: 100,
      );
      expect(l.rounds, hasLength(3));
      final ids = [
        for (final r in l.rounds) ...[
          for (var i = 0; i < 3; i++) r.words[i].sessionId,
        ],
      ];
      expect(ids, [100, 101, 102, 103, 104, 105, 106, 107, 108]);
      expect(l.rounds[1].current.item.word, 'w3');
    });
  });
}
