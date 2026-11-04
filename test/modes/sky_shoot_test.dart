import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/input/pose_types.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/modes/sky_shoot.dart';

Duration ms(int v) => Duration(milliseconds: v);

/// Answers stand still at 0.2 / 0.5 / 0.8; the arrow position is a function
/// of time chosen by the test.
class FakeField implements SkyField {
  FakeField(this.arrow);
  final double Function(Duration t) arrow;

  @override
  int get answerCount => 3;
  @override
  double get sweepSpeed => 0;
  @override
  double arrowX(Duration t) => arrow(t);
  @override
  double answerX(int i, Duration t) => const [0.2, 0.5, 0.8][i];
}

ChoiceQuestion _q({int correct = 1}) => ChoiceQuestion(
  itemId: 'cat',
  form: QuestionForm.listenPickWord,
  ttsText: 'cat',
  choices: List.generate(
    3,
    (i) => ChoiceOption(itemId: 'i$i', showPicture: false, showWord: true),
  ),
  correctIndex: correct,
);

SkyShootRound _round(
  double Function(Duration t) arrow, {
  Duration latency = Duration.zero,
  int correct = 1,
}) => SkyShootRound(
  _q(correct: correct),
  timeLimit: const Duration(seconds: 30),
  field: FakeField(arrow),
  castLatency: latency,
)..start();

Confirmed shoot(int atMs) => Confirmed(0, at: ms(atMs));
Pulled pull(Hand h) => Pulled(h, at: Duration.zero);

void main() {
  test('starts aiming with 3 shots and no pulls', () {
    final r = _round((_) => 0.5);
    expect(r.phase, SkyPhase.aiming);
    expect(r.shotsLeft, 3);
    expect(r.hitIndex, isNull);
    expect(r.pulls, 0);
    expect(r.result, isNull);
  });

  test('two misses cost two shots and keep aiming; the third ends it', () {
    final r = _round((_) => 0.35); // between answers: > 0.08 from 0.2 and 0.5
    r.onEvent(shoot(100));
    r.onEvent(shoot(900));
    expect(r.shotsLeft, 1);
    expect(r.phase, SkyPhase.aiming);
    expect(r.result, isNull);
    r.onEvent(shoot(1700));
    expect(r.shotsLeft, 0);
    expect(r.result, RoundResult.wrong);
    expect(r.phase, SkyPhase.resolved);
  });

  test('a hit goes to reeling, stops the clock and remembers the answer', () {
    final r = _round((_) => 0.52);
    r.tick(const Duration(seconds: 3));
    r.onEvent(shoot(100));
    expect(r.phase, SkyPhase.reeling);
    expect(r.hitIndex, 1);
    expect(r.shotsLeft, 3, reason: 'a hit does not cost a shot');
    expect(r.clockRunning, isFalse);
    r.tick(const Duration(seconds: 15));
    expect(r.result, isNull, reason: 'the question clock is stopped');
    expect(r.remaining, const Duration(seconds: 27));
  });

  test('a shot at the edge of the hit radius hits, just outside misses', () {
    final inside = _round((_) => 0.5 + 0.0799)..onEvent(shoot(0));
    expect(inside.phase, SkyPhase.reeling);
    final outside = _round((_) => 0.5 + 0.0801)..onEvent(shoot(0));
    expect(outside.phase, SkyPhase.aiming);
    expect(outside.shotsLeft, 2);
  });

  test('the shot is scored at the arrow position of (at - castLatency)', () {
    // The arrow is over the right answer until 1000 ms, then it has moved on.
    double arrow(Duration t) => t <= ms(1000) ? 0.5 : 0.9;
    // The child jumped when the arrow was over the answer, but the event only
    // arrives (frame time) 300 ms later.
    final withLatency = _round(arrow, latency: ms(300))..onEvent(shoot(1300));
    expect(withLatency.phase, SkyPhase.reeling);
    expect(withLatency.hitIndex, 1);
    // Without the measured latency the same event is a miss.
    final noLatency = _round(arrow)..onEvent(shoot(1300));
    expect(noLatency.phase, SkyPhase.aiming);
  });

  test('right answer + left, right, left, right -> correct', () {
    final r = _round((_) => 0.5)..onEvent(shoot(0));
    for (final h in [Hand.left, Hand.right, Hand.left]) {
      r.onEvent(pull(h));
      expect(r.result, isNull);
    }
    expect(r.pulls, 3);
    r.onEvent(pull(Hand.right));
    expect(r.pulls, 4);
    expect(r.result, RoundResult.correct);
    expect(r.phase, SkyPhase.resolved);
    expect(r.chosenIndex, 1);
  });

  test('the same hand twice in a row counts once', () {
    final r = _round((_) => 0.5)..onEvent(shoot(0));
    r.onEvent(pull(Hand.left));
    r.onEvent(pull(Hand.left));
    expect(r.pulls, 1);
    r.onEvent(pull(Hand.right));
    expect(r.pulls, 2);
  });

  test('wrong answer hit and fully reeled in -> wrong', () {
    final r = _round((_) => 0.2)..onEvent(shoot(0));
    expect(r.hitIndex, 0);
    for (final h in [Hand.left, Hand.right, Hand.left, Hand.right]) {
      r.onEvent(pull(h));
    }
    expect(r.result, RoundResult.wrong);
    expect(r.chosenIndex, 0);
  });

  test('pulls while aiming do not count', () {
    final r = _round((_) => 0.5);
    r.onEvent(pull(Hand.left));
    r.onEvent(pull(Hand.right));
    expect(r.pulls, 0);
    r.onEvent(shoot(0));
    r.onEvent(pull(Hand.left));
    expect(r.pulls, 1, reason: 'the first beat after the hit may be any hand');
  });

  test('Confirmed while reeling or resolved is ignored', () {
    final r = _round((_) => 0.5)..onEvent(shoot(0));
    r.onEvent(shoot(10));
    expect(r.phase, SkyPhase.reeling);
    expect(r.shotsLeft, 3);
    expect(r.hitIndex, 1);
    for (final h in [Hand.left, Hand.right, Hand.left, Hand.right]) {
      r.onEvent(pull(h));
    }
    r.onEvent(shoot(20));
    expect(r.result, RoundResult.correct);
    expect(r.shotsLeft, 3);
  });

  test('time runs out while aiming -> timeout', () {
    final r = _round((_) => 0.35);
    r.tick(const Duration(seconds: 29));
    expect(r.result, isNull);
    expect(r.elapsedFraction, closeTo(29 / 30, 1e-9));
    r.tick(const Duration(seconds: 2));
    expect(r.result, RoundResult.timeout);
    expect(r.remaining, Duration.zero);
  });

  test('before start() and while the player is lost nothing is graded', () {
    final r = SkyShootRound(
      _q(),
      timeLimit: const Duration(seconds: 30),
      field: FakeField((_) => 0.5),
      castLatency: Duration.zero,
    );
    r.onEvent(shoot(0));
    expect(r.phase, SkyPhase.aiming);
    expect(r.shotsLeft, 3);
    r.tick(const Duration(seconds: 40));
    expect(r.result, isNull);
    r.start();
    r.onEvent(const PlayerLost(at: Duration.zero));
    expect(r.clockRunning, isFalse);
    r.onEvent(shoot(0));
    r.tick(const Duration(seconds: 40));
    expect(r.phase, SkyPhase.aiming);
    expect(r.shotsLeft, 3);
    expect(r.result, isNull);
    r.onEvent(const PlayerFound(at: Duration.zero));
    r.onEvent(shoot(0));
    expect(r.phase, SkyPhase.reeling);
  });

  test('pulls are ignored while the player is lost', () {
    final r = _round((_) => 0.5)..onEvent(shoot(0));
    r.onEvent(const PlayerLost(at: Duration.zero));
    r.onEvent(pull(Hand.left));
    expect(r.pulls, 0);
  });

  test('result never changes once set', () {
    final r = _round((_) => 0.35);
    for (var i = 0; i < 3; i++) {
      r.onEvent(shoot(i));
    }
    expect(r.result, RoundResult.wrong);
    r.onEvent(pull(Hand.left));
    r.tick(const Duration(minutes: 5));
    expect(r.result, RoundResult.wrong);
  });

  group('SkyField', () {
    test('the arrow stays within 0.1..0.9', () {
      final f = SkyField(rng: Random(1), answerCount: 3, sweepSpeed: 0.4);
      for (var t = 0; t < 60000; t += 37) {
        expect(f.arrowX(ms(t)), inInclusiveRange(0.1 - 1e-9, 0.9 + 1e-9));
      }
    });

    test('speed is within +-20% of sweepSpeed', () {
      for (var seed = 0; seed < 30; seed++) {
        final f = SkyField(rng: Random(seed), answerCount: 3, sweepSpeed: 0.5);
        // Near the start (no reflection within 0.2 s) the slope is the speed.
        final v = (f.arrowX(ms(200)) - f.arrowX(Duration.zero)).abs() / 0.2;
        expect(v, inInclusiveRange(0.4 - 1e-6, 0.6 + 1e-6));
      }
    });

    test('with Random(7) over 50 questions both directions occur', () {
      final rng = Random(7);
      var left = 0, right = 0;
      for (var i = 0; i < 50; i++) {
        final f = SkyField(rng: rng, answerCount: 3, sweepSpeed: 0.4);
        final d = f.arrowX(ms(50)) - f.arrowX(Duration.zero);
        if (d < 0) left++;
        if (d > 0) right++;
      }
      expect(left, greaterThan(0));
      expect(right, greaterThan(0));
    });

    test('the arrow bounces: it reverses at the edges', () {
      final f = SkyField(rng: Random(3), answerCount: 3, sweepSpeed: 0.8);
      var lastDir = 0.0;
      var flips = 0;
      var prev = f.arrowX(Duration.zero);
      for (var t = 10; t < 10000; t += 10) {
        final x = f.arrowX(ms(t));
        final dir = (x - prev).sign;
        if (dir != 0) {
          if (lastDir != 0 && dir != lastDir) flips++;
          lastDir = dir;
        }
        prev = x;
      }
      expect(flips, greaterThan(3));
    });

    test('answers drift slowly and never overlap', () {
      for (final n in [3, 4]) {
        for (var seed = 0; seed < 20; seed++) {
          final f = SkyField(
            rng: Random(seed),
            answerCount: n,
            sweepSpeed: 0.4,
          );
          for (var t = 0; t < 40000; t += 250) {
            final xs = [for (var i = 0; i < n; i++) f.answerX(i, ms(t))];
            for (var i = 0; i < n; i++) {
              expect(xs[i], inInclusiveRange(0.05, 0.95));
              if (i > 0) {
                expect(
                  xs[i] - xs[i - 1],
                  greaterThan(2 * 0.08 + 0.005),
                  reason:
                      'n=$n seed=$seed t=$t: neighbours must be apart by '
                      'more than two hit radii so one shot hits one answer',
                );
              }
            }
          }
          // slow: under 0.05 per second
          final v = (f.answerX(0, ms(1000)) - f.answerX(0, ms(0))).abs();
          expect(v, lessThan(0.05));
        }
      }
    });
  });

  group('reeling timeout', () {
    SkyShootRound reeling({Duration timeout = const Duration(seconds: 20)}) {
      final r = SkyShootRound(
        _q(),
        timeLimit: const Duration(seconds: 30),
        field: FakeField((_) => 0.5),
        castLatency: Duration.zero,
        reelTimeout: timeout,
      )..start();
      r.onEvent(shoot(0));
      expect(r.phase, SkyPhase.reeling);
      return r;
    }

    test('no pull for reelTimeout -> timeout (not wrong)', () {
      final r = reeling();
      r.tick(const Duration(seconds: 19));
      expect(r.result, isNull);
      r.tick(const Duration(seconds: 2));
      expect(r.result, RoundResult.timeout);
      expect(r.phase, SkyPhase.resolved);
      expect(r.chosenIndex, isNull);
    });

    test('a counted pull restarts the idle timer', () {
      final r = reeling();
      r.tick(const Duration(seconds: 15));
      r.onEvent(pull(Hand.left));
      r.tick(const Duration(seconds: 15));
      expect(r.result, isNull);
      r.tick(const Duration(seconds: 6));
      expect(r.result, RoundResult.timeout);
    });

    test('stands still while the player is lost', () {
      final r = reeling();
      r.onEvent(const PlayerLost(at: Duration.zero));
      r.tick(const Duration(seconds: 60));
      expect(r.result, isNull);
      r.onEvent(const PlayerFound(at: Duration.zero));
      r.tick(const Duration(seconds: 19));
      expect(r.result, isNull);
    });

    test('the question clock still stands still while reeling', () {
      final r = reeling();
      r.tick(const Duration(seconds: 5));
      expect(r.remaining, const Duration(seconds: 30));
    });
  });
}
