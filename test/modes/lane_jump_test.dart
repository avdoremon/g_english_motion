import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/modes/lane_jump.dart';
import 'package:g_english_motion/modes/round.dart';

ChoiceQuestion _q({int correct = 2}) => ChoiceQuestion(
  itemId: 'cat',
  form: QuestionForm.listenPickWord,
  ttsText: 'cat',
  choices: List.generate(
    3,
    (i) => ChoiceOption(itemId: 'i$i', showPicture: false, showWord: true),
  ),
  correctIndex: correct,
);

const _t0 = Duration.zero;

LaneJumpRound _round({int initialLane = 0}) => LaneJumpRound(
  _q(),
  timeLimit: const Duration(seconds: 10),
  initialLane: initialLane,
);

void main() {
  test('correct lane after start -> correct', () {
    final r = _round()..start();
    r.onEvent(const Confirmed(2, at: _t0));
    expect(r.result, RoundResult.correct);
    expect(r.chosenIndex, 2);
  });

  test('wrong lane -> wrong', () {
    final r = _round()..start();
    r.onEvent(const Confirmed(1, at: _t0));
    expect(r.result, RoundResult.wrong);
    expect(r.chosenIndex, 1);
  });

  test('Confirmed before start is ignored; clock not running', () {
    final r = _round();
    expect(r.clockRunning, isFalse);
    r.onEvent(const Confirmed(2, at: _t0));
    r.tick(const Duration(seconds: 20));
    expect(r.result, isNull);
    expect(r.remaining, const Duration(seconds: 10));
  });

  test('tick for timeLimit -> timeout', () {
    final r = _round()..start();
    expect(r.clockRunning, isTrue);
    r.tick(const Duration(seconds: 4));
    expect(r.remaining, const Duration(seconds: 6));
    expect(r.result, isNull);
    r.tick(const Duration(seconds: 6));
    expect(r.result, RoundResult.timeout);
    expect(r.chosenIndex, isNull);
    expect(r.clockRunning, isFalse);
  });

  test('PlayerLost pauses clock and ignores Confirmed until PlayerFound', () {
    final r = _round()..start();
    r.onEvent(const PlayerLost(at: _t0));
    expect(r.clockRunning, isFalse);
    r.tick(const Duration(seconds: 5));
    expect(r.remaining, const Duration(seconds: 10));
    r.onEvent(const Confirmed(2, at: _t0));
    expect(r.result, isNull);
    r.onEvent(const PlayerFound(at: _t0));
    expect(r.clockRunning, isTrue);
    r.tick(const Duration(seconds: 5));
    expect(r.remaining, const Duration(seconds: 5));
    r.onEvent(const Confirmed(2, at: _t0));
    expect(r.result, RoundResult.correct);
  });

  test('result is final', () {
    final r = _round()..start();
    r.onEvent(const Confirmed(1, at: _t0));
    r.onEvent(const Confirmed(2, at: _t0));
    r.tick(const Duration(seconds: 30));
    expect(r.result, RoundResult.wrong);
    expect(r.chosenIndex, 1);
  });

  test('LaneChanged updates selectedLane, clamped', () {
    final r = _round();
    r.onEvent(const LaneChanged(1, at: _t0));
    expect(r.selectedLane, 1);
    r.onEvent(const LaneChanged(9, at: _t0));
    expect(r.selectedLane, 2);
    r.onEvent(const LaneChanged(-3, at: _t0));
    expect(r.selectedLane, 0);
  });

  test('initialLane clamped', () {
    expect(_round(initialLane: 7).selectedLane, 2);
    expect(_round(initialLane: -1).selectedLane, 0);
  });

  test('Confirmed uses its own lane, not selectedLane', () {
    final r = _round(initialLane: 0)..start();
    r.onEvent(const Confirmed(2, at: _t0));
    expect(r.result, RoundResult.correct);
  });

  test('Confirmed with out-of-range lane is ignored (not wrong)', () {
    final r = _round()..start();
    r.onEvent(const Confirmed(5, at: _t0));
    r.onEvent(const Confirmed(-1, at: _t0));
    expect(r.result, isNull);
    r.onEvent(const Confirmed(2, at: _t0));
    expect(r.result, RoundResult.correct);
  });

  test('overshooting tick clamps remaining at zero and times out', () {
    final r = _round()..start();
    r.tick(const Duration(seconds: 15)); // limit is 10 s
    expect(r.remaining, Duration.zero);
    expect(r.result, RoundResult.timeout);
    expect(r.clockRunning, isFalse);
  });

  test('zero and negative dt are ignored', () {
    final r = _round()..start();
    r.tick(const Duration(seconds: 3));
    r.tick(Duration.zero);
    r.tick(const Duration(seconds: -5));
    expect(r.remaining, const Duration(seconds: 7));
    expect(r.result, isNull);
  });

  test('a Confirmed applied before the tick of the same frame wins', () {
    // Contract (see Round): the caller applies a frame's events first, then
    // ticks, so an answer given on the last frame is not a timeout.
    final r = _round()..start();
    r.tick(const Duration(milliseconds: 9990));
    r.onEvent(const Confirmed(2, at: _t0));
    r.tick(const Duration(milliseconds: 100));
    expect(r.result, RoundResult.correct);
    expect(r.remaining, const Duration(milliseconds: 10));
  });

  test('a question without choices is rejected', () {
    const empty = ChoiceQuestion(
      itemId: 'cat',
      form: QuestionForm.listenPickWord,
      ttsText: 'cat',
      choices: [],
      correctIndex: 0,
    );
    expect(
      () => LaneJumpRound(
        empty,
        timeLimit: const Duration(seconds: 10),
        initialLane: 0,
      ),
      throwsA(isA<AssertionError>()),
    );
  });

  group('elapsedFraction / timeLimit (time-based, not frame-based)', () {
    test('timeLimit is exposed and the fraction is 0 before start', () {
      final r = _round();
      expect(r.timeLimit, const Duration(seconds: 10));
      expect(r.elapsedFraction, 0);
      r.tick(const Duration(seconds: 3)); // clock not running
      expect(r.elapsedFraction, 0);
    });

    test('follows the elapsed time whatever the tick size', () {
      for (final step in [16, 67, 250]) {
        final r = _round()..start();
        var spent = 0;
        while (spent < 5000) {
          r.tick(Duration(milliseconds: step));
          spent += step;
        }
        expect(
          r.elapsedFraction,
          closeTo(spent / 10000, 1e-9),
          reason: '$step',
        );
      }
    });

    test('is exactly 0.5 after half the time limit', () {
      final r = _round()..start();
      r.tick(const Duration(seconds: 5));
      expect(r.elapsedFraction, 0.5);
    });

    test('freezes while the player is lost and reaches 1 on timeout', () {
      final r = _round()..start();
      r.tick(const Duration(seconds: 2));
      r.onEvent(const PlayerLost(at: _t0));
      r.tick(const Duration(seconds: 5));
      expect(r.elapsedFraction, closeTo(0.2, 1e-9));
      r.onEvent(const PlayerFound(at: _t0));
      r.tick(const Duration(seconds: 30));
      expect(r.result, RoundResult.timeout);
      expect(r.elapsedFraction, 1.0);
    });
  });
}
