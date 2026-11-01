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
}
