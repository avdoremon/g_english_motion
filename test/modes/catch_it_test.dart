import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/modes/catch_it.dart';
import 'package:g_english_motion/modes/round.dart';

ChoiceQuestion _q({int correct = 2}) => ChoiceQuestion(
  itemId: 'cat',
  form: QuestionForm.listenPickPicture,
  ttsText: 'cat',
  choices: List.generate(
    3,
    (i) => ChoiceOption(itemId: 'i$i', showPicture: true, showWord: false),
  ),
  correctIndex: correct,
);

const _t0 = Duration.zero;
const _limit = Duration(seconds: 10);

CatchItRound _round({int initialLane = 0}) =>
    CatchItRound(_q(), timeLimit: _limit, initialLane: initialLane);

void main() {
  test('correct lane at the catch line -> correct', () {
    final r = _round(initialLane: 1)..start();
    r.onEvent(const LaneChanged(2, at: _t0));
    r.tick(_limit);
    expect(r.result, RoundResult.correct);
    expect(r.chosenIndex, 2);
  });

  test('wrong lane at the catch line -> wrong, never timeout', () {
    final r = _round()..start();
    r.tick(_limit);
    expect(r.result, RoundResult.wrong);
    expect(r.chosenIndex, 0);
  });

  test('Confirmed is ignored (no early answer)', () {
    final r = _round()..start();
    r.onEvent(const Confirmed(2, at: _t0));
    expect(r.result, isNull);
    r.tick(_limit);
    expect(r.result, RoundResult.wrong);
  });

  test('lane change after the catch line is ignored', () {
    final r = _round()..start();
    r.tick(_limit);
    r.onEvent(const LaneChanged(2, at: _t0));
    expect(r.result, RoundResult.wrong);
    expect(r.lane, 0);
  });

  test('lane change in the last frame counts (events before tick)', () {
    final r = _round()..start();
    r.tick(const Duration(seconds: 9));
    r.onEvent(const LaneChanged(2, at: _t0));
    r.tick(const Duration(seconds: 1));
    expect(r.result, RoundResult.correct);
  });

  test('fallFraction tracks elapsed and freezes while the player is lost', () {
    final r = _round()..start();
    expect(r.fallFraction, 0);
    r.tick(const Duration(seconds: 5));
    expect(r.fallFraction, closeTo(0.5, 1e-9));
    r.onEvent(const PlayerLost(at: _t0));
    r.tick(const Duration(seconds: 3));
    expect(r.fallFraction, closeTo(0.5, 1e-9));
    r.onEvent(const PlayerFound(at: _t0));
    r.tick(const Duration(seconds: 2));
    expect(r.fallFraction, closeTo(0.7, 1e-9));
  });

  test('clock does not run before start', () {
    final r = _round();
    r.tick(_limit);
    expect(r.result, isNull);
    expect(r.fallFraction, 0);
  });

  test('result is set once', () {
    final r = _round(initialLane: 2)..start();
    r.tick(_limit);
    r.onEvent(const LaneChanged(0, at: _t0));
    r.tick(const Duration(seconds: 1));
    expect(r.result, RoundResult.correct);
    expect(r.chosenIndex, 2);
  });

  test('zero or negative tick ignored; oversize tick clamps and resolves', () {
    final r = _round(initialLane: 2)..start();
    r.tick(Duration.zero);
    r.tick(const Duration(seconds: -1));
    expect(r.fallFraction, 0);
    r.tick(const Duration(seconds: 99));
    expect(r.remaining, Duration.zero);
    expect(r.fallFraction, 1.0);
    expect(r.result, RoundResult.correct);
  });
}
