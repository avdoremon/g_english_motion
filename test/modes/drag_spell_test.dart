import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/question_models.dart';
import 'package:g_english_motion/input/game_input_event.dart';
import 'package:g_english_motion/modes/drag_spell.dart';
import 'package:g_english_motion/modes/round.dart';

const _t0 = Duration.zero;
const _limit = Duration(seconds: 20);

// Scrambled tiles for "cat": a, t, c.
DragSpellRound _cat() => DragSpellRound.spell(
  const SpellQuestion(
    itemId: 'cat',
    ttsText: 'cat',
    word: 'cat',
    tiles: ['a', 't', 'c'],
  ),
  timeLimit: _limit,
)..start();

DragSpellRound _apple() => DragSpellRound.spell(
  const SpellQuestion(
    itemId: 'apple',
    ttsText: 'apple',
    word: 'apple',
    tiles: ['p', 'p', 'l', 'a', 'e'],
  ),
  timeLimit: _limit,
)..start();

DragSpellRound _order() => DragSpellRound.order(
  const OrderQuestion(
    itemId: 'the-cat',
    ttsText: 'the cat and the dog',
    words: ['cat', 'the', 'dog', 'and', 'the'],
    answer: ['the', 'cat', 'and', 'the', 'dog'],
  ),
  timeLimit: _limit,
)..start();

void place(DragSpellRound r, int tile, int slot) {
  r.onTargetHeld('tile:$tile');
  r.onTargetHeld('slot:$slot');
}

void main() {
  test('starts empty: slots null, nothing carried', () {
    final r = _cat();
    expect(r.slots, [null, null, null]);
    expect(r.carrying, isNull);
    expect(r.tiles, ['a', 't', 'c']);
    expect(r.result, isNull);
  });

  test('hold a tile then a slot -> the slot has the letter', () {
    final r = _cat();
    r.onTargetHeld('tile:0');
    expect(r.carrying, 'a');
    r.onTargetHeld('slot:1');
    expect(r.slots, [null, 'a', null]);
    expect(r.carrying, isNull);
    expect(r.isTileUsed(0), isTrue);
  });

  test('holding a filled slot picks its letter up again', () {
    final r = _cat();
    place(r, 0, 1);
    r.onTargetHeld('slot:1');
    expect(r.carrying, 'a');
    expect(r.slots, [null, null, null]);
    expect(r.carryingTile, 0, reason: 'the tile is in the hand');
  });

  test('holding a filled slot while carrying swaps', () {
    final r = _cat();
    place(r, 0, 0);
    r.onTargetHeld('tile:1');
    r.onTargetHeld('slot:0');
    expect(r.slots, ['t', null, null]);
    expect(r.carrying, 'a');
  });

  test('holding another tile replaces the carried one', () {
    final r = _cat();
    r.onTargetHeld('tile:0');
    r.onTargetHeld('tile:2');
    expect(r.carrying, 'c');
    expect(r.isTileUsed(0), isFalse);
  });

  test('a tile already placed cannot be picked from the tray', () {
    final r = _cat();
    place(r, 0, 0);
    r.onTargetHeld('tile:0');
    expect(r.carrying, isNull);
  });

  test('holding an empty slot with nothing in hand does nothing', () {
    final r = _cat();
    r.onTargetHeld('slot:2');
    expect(r.slots, [null, null, null]);
    expect(r.carrying, isNull);
  });

  test('unknown or out-of-range targets are ignored', () {
    final r = _cat();
    for (final id in ['tile:9', 'slot:-1', 'slot:x', 'bogus', 'tile:']) {
      r.onTargetHeld(id);
    }
    expect(r.slots, [null, null, null]);
    expect(r.carrying, isNull);
    expect(r.result, isNull);
  });

  test('check while not full gives no result', () {
    final r = _cat();
    place(r, 2, 0);
    r.onTargetHeld('check');
    expect(r.result, isNull);
    r.onTargetHeld('tile:0');
    r.onTargetHeld('check');
    expect(r.result, isNull, reason: 'a tile in hand, slots not full');
  });

  test('full and right -> correct', () {
    final r = _cat();
    place(r, 2, 0);
    place(r, 0, 1);
    place(r, 1, 2);
    r.onTargetHeld('check');
    expect(r.result, RoundResult.correct);
  });

  test('full and wrong -> wrong', () {
    final r = _cat();
    place(r, 0, 0);
    place(r, 1, 1);
    place(r, 2, 2);
    r.onTargetHeld('check');
    expect(r.result, RoundResult.wrong);
  });

  test('apple: the two p tiles are interchangeable', () {
    for (final ps in [
      [0, 1],
      [1, 0],
    ]) {
      final r = _apple();
      place(r, 3, 0); // a
      place(r, ps[0], 1); // p
      place(r, ps[1], 2); // p
      place(r, 2, 3); // l
      place(r, 4, 4); // e
      r.onTargetHeld('check');
      expect(r.result, RoundResult.correct);
    }
  });

  test('order: swapping the two "the" is still correct', () {
    // words: cat(0) the(1) dog(2) and(3) the(4)
    final r = _order();
    place(r, 4, 0);
    place(r, 0, 1);
    place(r, 3, 2);
    place(r, 1, 3);
    place(r, 2, 4);
    expect(r.slots, ['the', 'cat', 'and', 'the', 'dog']);
    r.onTargetHeld('check');
    expect(r.result, RoundResult.correct);
  });

  test(
    'order: tiles carry no trailing punctuation; the answer still grades',
    () {
      final r = DragSpellRound.order(
        const OrderQuestion(
          itemId: 'apples',
          ttsText: 'I like apples.',
          words: ['apples.', 'like', 'I'],
          answer: ['I', 'like', 'apples.'],
        ),
        timeLimit: _limit,
      )..start();
      expect(r.tiles, ['apples', 'like', 'I']);
      place(r, 2, 0);
      place(r, 1, 1);
      place(r, 0, 2);
      expect(r.slots, ['I', 'like', 'apples']);
      r.onTargetHeld('check');
      expect(r.result, RoundResult.correct);
    },
  );

  test('order: wrong order -> wrong', () {
    final r = _order();
    for (var i = 0; i < 5; i++) {
      place(r, i, i);
    }
    r.onTargetHeld('check');
    expect(r.result, RoundResult.wrong);
  });

  test('result never changes once set', () {
    final r = _cat();
    place(r, 0, 0);
    place(r, 1, 1);
    place(r, 2, 2);
    r.onTargetHeld('check');
    r.onTargetHeld('slot:0');
    expect(r.slots, ['a', 't', 'c']);
    r.tick(const Duration(minutes: 5));
    expect(r.result, RoundResult.wrong);
  });

  test('nothing counts before start()', () {
    final r = DragSpellRound.spell(
      const SpellQuestion(
        itemId: 'cat',
        ttsText: 'cat',
        word: 'cat',
        tiles: ['a', 't', 'c'],
      ),
      timeLimit: _limit,
    );
    r.onTargetHeld('tile:0');
    expect(r.carrying, isNull);
    r.tick(const Duration(seconds: 30));
    expect(r.result, isNull);
    expect(r.clockRunning, isFalse);
  });

  test('PlayerLost stops the clock and input until PlayerFound', () {
    final r = _cat();
    r.tick(const Duration(seconds: 5));
    r.onEvent(const PlayerLost(at: _t0));
    expect(r.clockRunning, isFalse);
    r.tick(const Duration(seconds: 30));
    expect(r.remaining, const Duration(seconds: 15));
    expect(r.result, isNull);
    r.onTargetHeld('tile:0');
    expect(r.carrying, isNull);
    r.onEvent(const PlayerFound(at: _t0));
    expect(r.clockRunning, isTrue);
    r.onTargetHeld('tile:0');
    expect(r.carrying, 'a');
  });

  test('running out of time -> timeout, with the elapsed fraction', () {
    final r = _cat();
    r.tick(const Duration(seconds: 5));
    expect(r.elapsedFraction, closeTo(0.25, 1e-9));
    r.tick(const Duration(seconds: 16));
    expect(r.result, RoundResult.timeout);
    expect(r.remaining, Duration.zero);
    expect(r.clockRunning, isFalse);
  });

  test('zero or negative ticks are ignored; other events do nothing', () {
    final r = _cat();
    r.tick(Duration.zero);
    r.tick(const Duration(seconds: -3));
    expect(r.remaining, _limit);
    r.onEvent(const Confirmed(1, at: _t0));
    r.onEvent(const CursorMoved(0.5, 0.5, at: _t0));
    expect(r.result, isNull);
  });

  test('chosenIndex is not used', () {
    expect(_cat().chosenIndex, isNull);
  });
}
