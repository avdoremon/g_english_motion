import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/modes/hold_pick.dart';
import 'package:g_english_motion/modes/round.dart';

ChoiceQuestion _q({int correct = 1, int n = 3}) => ChoiceQuestion(
  itemId: 'cat',
  form: QuestionForm.popWord,
  ttsText: 'cat',
  choices: List.generate(
    n,
    (i) => ChoiceOption(itemId: 'i$i', showPicture: true, showWord: false),
  ),
  correctIndex: correct,
);

/// Three side-by-side columns; centres at x = 1/6, 1/2, 5/6.
Rect _cols(int i) => Rect.fromLTWH(i / 3, 0, 1 / 3, 1);

const _limit = Duration(seconds: 10);
const _hold = Duration(seconds: 1);

HoldPickRound _round({
  Duration peek = Duration.zero,
  Rect Function(int)? rect,
  int correct = 1,
  Duration limit = _limit,
}) => HoldPickRound(
  _q(correct: correct),
  timeLimit: limit,
  holdTime: _hold,
  peek: peek,
  targetRect: rect ?? _cols,
);

Duration _ms(int ms) => Duration(milliseconds: ms);

CursorMoved _at(double x, int ms) => CursorMoved(x, 0.5, at: _ms(ms));

/// Cursor held at [x] from [fromMs] to [toMs] in 50 ms frames.
void _hover(HoldPickRound r, double x, int fromMs, int toMs) {
  for (var t = fromMs; t <= toMs; t += 50) {
    r.onEvent(_at(x, t));
  }
}

void main() {
  test('sweeping across three targets at 100 ms each never completes', () {
    final r = _round()..start();
    var t = 0;
    for (final x in [0.1, 0.5, 0.9, 0.5, 0.1, 0.9]) {
      _hover(r, x, t, t + 100);
      t += 150;
    }
    expect(r.result, isNull);
    expect(r.holdProgress, lessThan(0.5));
  });

  test('holding target 1 for 1 s picks it (correct)', () {
    final r = _round()..start();
    _hover(r, 0.5, 0, 900);
    expect(r.result, isNull);
    expect(r.hoverTarget, 'choice:1');
    expect(r.holdProgress, closeTo(0.9, 0.01));
    _hover(r, 0.5, 950, 1000);
    expect(r.chosenIndex, 1);
    expect(r.result, RoundResult.correct);
  });

  test('holding a wrong target grades wrong', () {
    final r = _round()..start();
    _hover(r, 0.1, 0, 1000);
    expect(r.chosenIndex, 0);
    expect(r.result, RoundResult.wrong);
  });

  test('leaving for < 200 ms keeps progress, >= 200 ms resets', () {
    final r = _round()..start();
    _hover(r, 0.5, 0, 500);
    r.onEvent(const CursorMoved(2, 2, at: Duration(milliseconds: 550)));
    expect(r.hoverTarget, isNull);
    _hover(r, 0.5, 600, 650);
    expect(r.holdProgress, greaterThan(0.5));

    final s = _round()..start();
    _hover(s, 0.5, 0, 500);
    s.onEvent(const CursorMoved(2, 2, at: Duration(milliseconds: 600)));
    s.onEvent(const CursorMoved(2, 2, at: Duration(milliseconds: 750)));
    _hover(s, 0.5, 800, 850);
    expect(s.holdProgress, lessThan(0.2));
  });

  test('overlapping rects pick the nearest centre', () {
    // Rects 0 and 1 overlap on x in [0.4, 0.6]; centres 0.3 and 0.7.
    Rect rect(int i) => i == 0
        ? const Rect.fromLTRB(0, 0, 0.6, 1)
        : i == 1
        ? const Rect.fromLTRB(0.4, 0, 1, 1)
        : const Rect.fromLTRB(2, 2, 3, 3);
    final r = _round(rect: rect)..start();
    r.onEvent(_at(0.45, 0));
    expect(r.hoverTarget, 'choice:0');
    r.onEvent(_at(0.55, 50));
    expect(r.hoverTarget, 'choice:1');
  });

  test('peek: clock and cursor are inert, peeking is true', () {
    final r = _round(peek: _ms(2000))..start();
    expect(r.peeking, isTrue);
    expect(r.clockRunning, isFalse);
    _hover(r, 0.5, 0, 1900);
    r.tick(_ms(1900));
    expect(r.result, isNull);
    expect(r.remaining, _limit);
    expect(r.hoverTarget, isNull);
    r.tick(_ms(100));
    expect(r.peeking, isFalse);
    expect(r.clockRunning, isTrue);
    r.tick(_ms(1000));
    expect(r.remaining, _ms(9000));
    // A hold that was "in progress" during the peek did not count.
    _hover(r, 0.5, 2000, 2500);
    expect(r.result, isNull);
    _hover(r, 0.5, 2550, 3000);
    expect(r.result, RoundResult.correct);
  });

  test('peek is counted only after start', () {
    final r = _round(peek: _ms(2000));
    r.tick(_ms(5000));
    expect(r.peeking, isFalse);
    r.start();
    expect(r.peeking, isTrue);
    r.tick(_ms(1000));
    expect(r.peeking, isTrue);
  });

  test('cursor before start is dropped; start resets hold state', () {
    final r = _round();
    _hover(r, 0.5, 0, 900);
    r.start();
    expect(r.hoverTarget, isNull);
    _hover(r, 0.5, 1000, 1500);
    expect(r.result, isNull);
  });

  test('PlayerLost mid-hold resets progress and freezes the clock', () {
    final r = _round()..start();
    _hover(r, 0.5, 0, 500);
    r.tick(_ms(500));
    r.onEvent(const PlayerLost(at: Duration(milliseconds: 500)));
    expect(r.holdProgress, 0);
    expect(r.hoverTarget, isNull);
    expect(r.clockRunning, isFalse);
    r.tick(_ms(3000));
    expect(r.remaining, _ms(9500));
    _hover(r, 0.5, 600, 2000);
    expect(r.result, isNull);
    r.onEvent(const PlayerFound(at: Duration(milliseconds: 2000)));
    expect(r.clockRunning, isTrue);
    _hover(r, 0.5, 2050, 2500);
    expect(r.result, isNull);
    _hover(r, 0.5, 2550, 3100);
    expect(r.result, RoundResult.correct);
  });

  test('timeout gives RoundResult.timeout', () {
    final r = _round()..start();
    r.tick(_limit);
    expect(r.result, RoundResult.timeout);
    expect(r.chosenIndex, isNull);
  });

  test('onTargetHeld grades like a completed hold', () {
    final r = _round()..start();
    r.onTargetHeld('choice:2');
    expect(r.chosenIndex, 2);
    expect(r.result, RoundResult.wrong);
    final c = _round()..start();
    c.onTargetHeld('choice:1');
    expect(c.result, RoundResult.correct);
  });

  test('a second pick after the result is ignored', () {
    final r = _round()..start();
    r.onTargetHeld('choice:2');
    r.onTargetHeld('choice:1');
    _hover(r, 0.5, 0, 1200);
    expect(r.chosenIndex, 2);
    expect(r.result, RoundResult.wrong);
  });

  test('onTargetHeld ignored during peek, before start and for bad ids', () {
    final r = _round(peek: _ms(2000));
    r.onTargetHeld('choice:1');
    r.start();
    r.onTargetHeld('choice:1');
    expect(r.result, isNull);
    r.tick(_ms(2000));
    r.onTargetHeld('choice:9');
    r.onTargetHeld('tile:1');
    r.onTargetHeld('choice:x');
    expect(r.result, isNull);
    r.onTargetHeld('choice:1');
    expect(r.result, RoundResult.correct);
  });
}
