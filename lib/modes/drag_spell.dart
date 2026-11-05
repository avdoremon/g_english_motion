import '../content/question_models.dart';
import '../input/game_input_event.dart';
import 'round.dart';

/// Drag-and-drop spelling / sentence ordering (grades 3-5).
///
/// The UI turns the cursor position into a target id and calls
/// [onTargetHeld] once the player has held it long enough (see
/// `HoldTracker`):
/// - `tile:<i>`: pick up tile i from the tray (replaces what is in hand);
/// - `slot:<i>`: with a tile in hand put it in the slot (a letter already
///   there goes to the hand instead); with an empty hand pick the slot's tile
///   up again;
/// - `check`: grade the answer, but only when every slot is filled.
///
/// Tiles are tracked by index, so equal letters/words (the two p of "apple",
/// the two "the" of a sentence) are interchangeable: the answer is compared
/// by text. Input that is not understood (unknown id, tile not available,
/// check on an incomplete answer) is ignored, never graded.
/// A sentence word without the punctuation around it ("apples." -> "apples"):
/// a tile must not hint that it is the last word. Inner marks ("don't") stay.
String _stripPunctuation(String w) {
  final s = w.replaceAll(
    RegExp(r'^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$', unicode: true),
    '',
  );
  return s.isEmpty ? w : s;
}

/// A real guard (asserts are stripped in release): a tile count that does not
/// match the answer would make an unwinnable round.
List<String> _requireCount(List<String> tiles, int expected, String message) {
  if (tiles.length != expected) throw ArgumentError(message);
  return tiles;
}

class DragSpellRound implements Round {
  DragSpellRound.spell(SpellQuestion q, {required this.timeLimit})
    : tiles = List.unmodifiable(
        _requireCount(
          q.tiles,
          q.word.runes.length,
          'spell: ${q.tiles.length} tiles cannot spell "${q.word}" '
          '(${q.word.runes.length} letters)',
        ),
      ),
      _answer = [for (final r in q.word.runes) String.fromCharCode(r)],
      _slots = List<int?>.filled(q.tiles.length, null),
      _remaining = timeLimit;

  DragSpellRound.order(OrderQuestion q, {required this.timeLimit})
    : tiles = List.unmodifiable(
        _requireCount(
          q.words,
          q.answer.length,
          'order: ${q.words.length} tiles cannot build a ${q.answer.length}'
          '-word answer',
        ).map(_stripPunctuation),
      ),
      _answer = List.unmodifiable(q.answer.map(_stripPunctuation)),
      _slots = List<int?>.filled(q.words.length, null),
      _remaining = timeLimit;

  /// The tray: letters or words, in their (shuffled) display order.
  final List<String> tiles;
  final List<String> _answer;

  /// Tray index placed in each slot (null: empty).
  final List<int?> _slots;
  int? _carrying;

  Duration _remaining;
  bool _started = false;
  bool _playerPresent = true;
  RoundResult? _result;

  static final RegExp _target = RegExp(r'^(tile|slot):(\d+)$');

  /// Text in each slot (null: empty).
  List<String?> get slots => [
    for (final i in _slots) i == null ? null : tiles[i],
  ];

  /// Tray index in each slot (null: empty); for the UI.
  List<int?> get slotTiles => List.unmodifiable(_slots);

  /// The tile in hand (text), if any.
  String? get carrying => _carrying == null ? null : tiles[_carrying!];

  /// Tray index of the tile in hand.
  int? get carryingTile => _carrying;

  /// Whether tile [i] is not in the tray any more (placed or in hand).
  bool isTileUsed(int i) => _carrying == i || _slots.contains(i);

  bool get isFull => !_slots.contains(null);

  @override
  RoundResult? get result => _result;

  @override
  int? get chosenIndex => null;

  @override
  Duration get remaining => _remaining;

  @override
  final Duration timeLimit;

  @override
  double get elapsedFraction {
    final limit = timeLimit.inMicroseconds;
    if (limit <= 0) return 1.0;
    return (1 - _remaining.inMicroseconds / limit).clamp(0.0, 1.0);
  }

  @override
  bool get clockRunning => _started && _playerPresent && _result == null;

  @override
  void start() => _started = true;

  @override
  void onEvent(GameInputEvent e) {
    if (_result != null) return;
    switch (e) {
      case PlayerLost():
        _playerPresent = false;
      case PlayerFound():
        _playerPresent = true;
      case LaneChanged() || Confirmed() || CursorMoved() || Pulled():
        break;
    }
  }

  /// The player held [targetId] long enough (or tapped it).
  void onTargetHeld(String targetId) {
    if (!_started || !_playerPresent || _result != null) return;
    if (targetId == 'check') {
      _check();
      return;
    }
    final m = _target.firstMatch(targetId);
    if (m == null) return;
    final i = int.parse(m.group(2)!);
    if (i >= tiles.length) return;
    if (m.group(1) == 'tile') {
      if (isTileUsed(i)) return;
      _carrying = i;
    } else {
      final inSlot = _slots[i];
      if (_carrying == null && inSlot == null) return;
      _slots[i] = _carrying;
      _carrying = inSlot;
    }
  }

  void _check() {
    // An incomplete answer is not an answer: nothing to grade yet.
    if (!isFull) return;
    final given = slots;
    var same = given.length == _answer.length;
    for (var i = 0; same && i < given.length; i++) {
      same = given[i] == _answer[i];
    }
    _result = same ? RoundResult.correct : RoundResult.wrong;
  }

  @override
  void tick(Duration dt) {
    if (dt <= Duration.zero || !clockRunning) return;
    _remaining -= dt;
    if (_remaining <= Duration.zero) {
      _remaining = Duration.zero;
      _result = RoundResult.timeout;
    }
  }
}
