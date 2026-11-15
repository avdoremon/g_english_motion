import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/input/pose_types.dart';
import 'package:g_english_motion/modes/round.dart';
import 'package:g_english_motion/modes/yes_no.dart';

ChoiceQuestion _q({int correct = 0}) => ChoiceQuestion(
  itemId: 'cat',
  form: QuestionForm.trueFalse,
  ttsText: 'This is a cat',
  promptText: 'This is a cat',
  promptImageItemId: 'cat',
  choices: const [
    ChoiceOption(itemId: 'cat', showPicture: false, showWord: false),
    ChoiceOption(itemId: 'cat', showPicture: false, showWord: false),
  ],
  correctIndex: correct,
);

const _t0 = Duration.zero;
const _limit = Duration(seconds: 10);
const _left = HandRaised(Hand.left, at: _t0);
const _right = HandRaised(Hand.right, at: _t0);

YesNoRound _round({int correct = 0}) =>
    YesNoRound(_q(correct: correct), timeLimit: _limit);

void main() {
  test('left hand answers choice 0: correct when the statement is true', () {
    final r = _round()..start();
    r.onEvent(_left);
    expect(r.result, RoundResult.correct);
    expect(r.chosenIndex, 0);
  });

  test('left hand is wrong when the statement is false', () {
    final r = _round(correct: 1)..start();
    r.onEvent(_left);
    expect(r.result, RoundResult.wrong);
    expect(r.chosenIndex, 0);
  });

  test('right hand answers choice 1', () {
    final ok = _round(correct: 1)..start();
    ok.onEvent(_right);
    expect(ok.result, RoundResult.correct);
    expect(ok.chosenIndex, 1);
    final bad = _round()..start();
    bad.onEvent(_right);
    expect(bad.result, RoundResult.wrong);
    expect(bad.chosenIndex, 1);
  });

  test('events before start are ignored', () {
    final r = _round();
    r.onEvent(_left);
    r.answer(0);
    expect(r.result, isNull);
    r.start();
    r.onEvent(_right);
    expect(r.result, RoundResult.wrong);
  });

  test('a second hand after the first result never changes it', () {
    final r = _round()..start();
    r.onEvent(_left);
    r.onEvent(_right);
    r.answer(1);
    expect(r.result, RoundResult.correct);
    expect(r.chosenIndex, 0);
    final w = _round()..start();
    w.onEvent(_right);
    w.onEvent(_left);
    expect(w.result, RoundResult.wrong);
    expect(w.chosenIndex, 1);
  });

  test('events and answer while lost are ignored', () {
    final r = _round()..start();
    r.onEvent(const PlayerLost(at: _t0));
    r.onEvent(_left);
    r.answer(0);
    expect(r.result, isNull);
    r.onEvent(const PlayerFound(at: _t0));
    r.onEvent(_left);
    expect(r.result, RoundResult.correct);
  });

  test('answer is the touch fallback with the same grading', () {
    final r = _round(correct: 1)..start();
    r.answer(1);
    expect(r.result, RoundResult.correct);
    expect(r.chosenIndex, 1);
  });

  test('answer out of range is not graded', () {
    final r = _round()..start();
    r.answer(-1);
    r.answer(2);
    expect(r.result, isNull);
  });

  test('other events are ignored', () {
    final r = _round()..start();
    r.onEvent(const Confirmed(0, at: _t0));
    r.onEvent(const LaneChanged(1, at: _t0));
    r.onEvent(const Pulled(Hand.left, at: _t0));
    r.onEvent(const CursorMoved(0.5, 0.5, at: _t0));
    expect(r.result, isNull);
  });

  test('no answer by the time limit -> timeout', () {
    final r = _round()..start();
    r.tick(const Duration(seconds: 9));
    expect(r.result, isNull);
    r.tick(const Duration(seconds: 1));
    expect(r.result, RoundResult.timeout);
    expect(r.chosenIndex, isNull);
    expect(r.remaining, Duration.zero);
  });

  test('an answer in the last frame is graded (events before tick)', () {
    final r = _round()..start();
    r.tick(const Duration(seconds: 9));
    r.onEvent(_left);
    r.tick(const Duration(seconds: 1));
    expect(r.result, RoundResult.correct);
  });

  test('zero and negative ticks are ignored', () {
    final r = _round()..start();
    r.tick(Duration.zero);
    r.tick(const Duration(seconds: -3));
    expect(r.remaining, _limit);
    expect(r.elapsedFraction, 0);
  });

  test('an oversize tick clamps to timeout', () {
    final r = _round()..start();
    r.tick(const Duration(minutes: 5));
    expect(r.result, RoundResult.timeout);
    expect(r.remaining, Duration.zero);
    expect(r.elapsedFraction, 1);
  });

  test('result never changes after a timeout', () {
    final r = _round()..start();
    r.tick(_limit);
    r.onEvent(_left);
    r.answer(0);
    expect(r.result, RoundResult.timeout);
  });

  test('clock does not run before start', () {
    final r = _round();
    expect(r.clockRunning, isFalse);
    r.tick(const Duration(seconds: 5));
    expect(r.remaining, _limit);
  });

  test('clock stops while lost and resumes on PlayerFound', () {
    final r = _round()..start();
    r.tick(const Duration(seconds: 4));
    r.onEvent(const PlayerLost(at: _t0));
    expect(r.clockRunning, isFalse);
    r.tick(const Duration(seconds: 100));
    expect(r.remaining, const Duration(seconds: 6));
    expect(r.result, isNull);
    r.onEvent(const PlayerFound(at: _t0));
    expect(r.clockRunning, isTrue);
    r.tick(const Duration(seconds: 6));
    expect(r.result, RoundResult.timeout);
  });

  test('clock stops once a result is set', () {
    final r = _round()..start();
    r.onEvent(_left);
    expect(r.clockRunning, isFalse);
  });
}
