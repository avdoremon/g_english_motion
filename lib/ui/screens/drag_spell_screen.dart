import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/game_controller.dart';
import '../../content/question_models.dart';
import '../../input/game_input_event.dart';
import '../../input/hold_tracker.dart';
import '../../levels/level_config.dart';
import '../../modes/drag_spell.dart';
import '../../modes/round.dart';
import '../../session/level_session.dart';
import '../mascot/tin_tin.dart';
import '../theme/app_theme.dart';
import 'lane_jump_screen.dart' show ItemPicture;
import 'play_header.dart';
import 'round_verdict.dart';

final Stopwatch _sw = Stopwatch()..start();
Duration _monotonic() => _sw.elapsed;

/// The DragSpell play screen (grades 3-5): spell a word from letter tiles, or
/// put the words of a sentence in order.
///
/// Controls:
/// - Pose: the raised wrist is the cursor ([CursorMoved]); holding it over a
///   tile, a slot or "Kiểm tra" for 1 s ([HoldTracker]) picks / drops / checks.
///   The cursor is drawn with a progress ring around it.
/// - Touch (fallback, so the game is playable without a camera): tapping a
///   tile picks it up, tapping a slot drops it (or picks its letter up),
///   tapping "Kiểm tra" checks.
///
/// The word / sentence being asked is never shown or announced before the
/// answer is given: the question is read aloud only, the hint picture is the
/// same one the level's hint mode allows, and the tiles' semantics name only
/// the tile itself.
class DragSpellScreen extends StatefulWidget {
  const DragSpellScreen({
    super.key,
    required this.controller,
    this.onExit,
    this.clock,
  });

  final GameController controller;
  final VoidCallback? onExit;

  /// Monotonic clock for the hold timing (injectable for tests).
  final Duration Function()? clock;

  /// No cursor update for this long: the hand is gone, nothing is held.
  static const cursorStale = Duration(milliseconds: 400);

  @override
  State<DragSpellScreen> createState() => _DragSpellScreenState();
}

class _DragSpellScreenState extends State<DragSpellScreen> {
  final HoldTracker _hold = HoldTracker();
  final GlobalKey _boardKey = GlobalKey();
  final Map<String, GlobalKey> _keys = {};
  StreamSubscription<GameInputEvent>? _sub;
  Round? _round;

  Offset? _cursor;
  Duration _cursorAt = Duration.zero;
  bool _cursorSeen = false;
  HoldProgress _progress = const HoldProgress(
    targetId: null,
    progress: 0,
    completed: false,
  );
  bool _cursorVisible = false;

  /// Cursor position drawn last (a repaint is needed only when it moves).
  Offset? _shownCursor;

  Duration _now() => (widget.clock ?? _monotonic)();

  GlobalKey _keyFor(String id) => _keys.putIfAbsent(id, GlobalKey.new);

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.events.listen(_onEvent);
    widget.controller.hudTick.addListener(_tick);
  }

  @override
  void didUpdateWidget(DragSpellScreen old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _sub?.cancel();
      old.controller.hudTick.removeListener(_tick);
      _sub = widget.controller.events.listen(_onEvent);
      widget.controller.hudTick.addListener(_tick);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.controller.hudTick.removeListener(_tick);
    super.dispose();
  }

  void _onEvent(GameInputEvent e) {
    if (e is CursorMoved) {
      _cursor = Offset(e.x, e.y);
      _cursorAt = _now();
      _cursorSeen = true;
    }
  }

  /// Which target is under the normalized cursor [c], if any.
  String? _hit(Offset c, DragSpellRound round) {
    final board = _boardKey.currentContext?.findRenderObject();
    if (board is! RenderBox || !board.hasSize) return null;
    final point = board.localToGlobal(
      Offset(c.dx * board.size.width, c.dy * board.size.height),
    );
    bool over(String id) {
      final ro = _keys[id]?.currentContext?.findRenderObject();
      if (ro is! RenderBox || !ro.hasSize || !ro.attached) return false;
      final rect = (ro.localToGlobal(Offset.zero) & ro.size).inflate(6);
      return rect.contains(point);
    }

    for (var i = 0; i < round.tiles.length; i++) {
      if (!round.isTileUsed(i) && over('tile:$i')) return 'tile:$i';
    }
    for (var i = 0; i < round.tiles.length; i++) {
      if (over('slot:$i')) return 'slot:$i';
    }
    if (round.isFull && over('check')) return 'check';
    return null;
  }

  /// Follows the 60 Hz tick of the controller while playing.
  void _tick() {
    if (!mounted) return;
    final s = widget.controller.session;
    final round = s?.round;
    if (s == null ||
        s.phase != SessionPhase.playing ||
        round is! DragSpellRound) {
      _stopHolding();
      return;
    }
    if (!identical(round, _round)) {
      _round = round;
      _hold.reset();
    }
    if (!round.clockRunning) {
      // Player lost / paused: nothing is held, nothing is graded.
      _stopHolding();
      return;
    }
    final now = _now();
    final c = _cursor;
    final fresh =
        _cursorSeen &&
        c != null &&
        now - _cursorAt <= DragSpellScreen.cursorStale;
    final target = fresh ? _hit(c, round) : null;
    final p = _hold.update(target, now);
    final shown = fresh ? c : null;
    final changed =
        p.targetId != _progress.targetId ||
        p.progress != _progress.progress ||
        fresh != _cursorVisible ||
        shown != _shownCursor;
    _progress = p;
    _cursorVisible = fresh;
    _shownCursor = shown;
    if (p.completed && p.targetId != null) {
      widget.controller.holdTarget(p.targetId!);
    }
    if (changed && mounted) setState(() {});
  }

  void _stopHolding() {
    _hold.reset();
    if (_progress.targetId != null || _cursorVisible) {
      _progress = const HoldProgress(
        targetId: null,
        progress: 0,
        completed: false,
      );
      _cursorVisible = false;
      if (mounted) setState(() {});
    }
  }

  void _tap(String id) {
    widget.controller.holdTarget(id);
    _hold.reset();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final s = widget.controller.session;
        if (s == null || s.phase == SessionPhase.finished) {
          return const SizedBox.shrink();
        }
        final q = s.current.question;
        final round = s.round;
        if (round is! DragSpellRound ||
            (q is! SpellQuestion && q is! OrderQuestion)) {
          return const SizedBox.shrink();
        }
        return _board(context, s, q, round);
      },
    );
  }

  Widget _board(
    BuildContext context,
    LevelSession s,
    Question q,
    DragSpellRound round,
  ) {
    final feedback = s.phase == SessionPhase.feedback;
    // The board's own size comes from this LayoutBuilder, never from its
    // render object: reading that during build gives the PREVIOUS frame's
    // size (Size.zero on the first one), which would misplace the cursor.
    return LayoutBuilder(
      builder: (context, board) => Stack(
        key: _boardKey,
        children: [
          Positioned.fill(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, box) {
                  final compact = box.maxHeight < 420;
                  final gap = compact ? 6.0 : 12.0;
                  final inner = box.maxWidth - 48;
                  final checkW = compact ? 150.0 : 200.0;
                  final n = round.tiles.length;
                  // Cells are sized from the text, not from the touch target
                  // alone: a whole word needs a wider cell than a letter.
                  final minCell = _minCellWidth(round.tiles);
                  final slotsPer = _cellsPerRow(n, inner, minCell);
                  final trayW = inner - 16 - checkW;
                  final trayPer = _cellsPerRow(n, trayW, minCell);
                  final slotRows = _rowCount(n, inner, minCell);
                  final trayRows = _rowCount(n, trayW, minCell);
                  return Padding(
                    padding: compact
                        ? const EdgeInsets.fromLTRB(24, 6, 24, 8)
                        : const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Column(
                      children: [
                        PlayHeader(
                          controller: widget.controller,
                          session: s,
                          onExit: widget.onExit,
                        ),
                        SizedBox(height: gap),
                        Expanded(
                          flex: 2,
                          child: _PromptRow(
                            controller: widget.controller,
                            session: s,
                            question: q,
                            round: round,
                            feedback: feedback,
                          ),
                        ),
                        SizedBox(height: gap),
                        Expanded(
                          flex: 2 * slotRows + 1,
                          child: _Slots(
                            screen: this,
                            round: round,
                            perRow: slotsPer,
                          ),
                        ),
                        SizedBox(height: gap),
                        Expanded(
                          flex: 2 * trayRows + 1,
                          child: Row(
                            children: [
                              Expanded(
                                child: _Tray(
                                  screen: this,
                                  round: round,
                                  perRow: trayPer,
                                ),
                              ),
                              const SizedBox(width: 16),
                              SizedBox(
                                width: checkW,
                                child: _CheckButton(
                                  screen: this,
                                  enabled: round.isFull,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
          if (_cursorVisible && _cursor != null)
            _cursorOverlay(round, board.biggest),
        ],
      ),
    );
  }

  Widget _cursorOverlay(DragSpellRound round, Size size) {
    final c = _cursor!;
    const d = 72.0;
    final holding = _progress.targetId != null;
    return Positioned(
      left: c.dx * size.width - d / 2,
      top: c.dy * size.height - d / 2,
      width: d,
      height: d,
      child: IgnorePointer(
        child: Semantics(
          label: 'Con trỏ tay',
          excludeSemantics: true,
          child: Stack(
            key: const ValueKey('cursor'),
            alignment: Alignment.center,
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: const BoxDecoration(
                  color: AppTheme.yellow,
                  shape: BoxShape.circle,
                ),
              ),
              if (holding)
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    key: const ValueKey('hold-ring'),
                    value: _progress.progress,
                    strokeWidth: 8,
                    color: AppTheme.green,
                    backgroundColor: AppTheme.surface,
                  ),
                ),
              if (round.carrying != null)
                Positioned(
                  top: -4,
                  right: -8,
                  child: _MiniChip(text: round.carrying!),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A small chip showing the tile in hand.
class _MiniChip extends StatelessWidget {
  const _MiniChip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      decoration: BoxDecoration(
        color: AppTheme.accent,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTheme.textStyles.label.copyWith(color: AppTheme.background),
      ),
    );
  }
}

class _PromptRow extends StatelessWidget {
  const _PromptRow({
    required this.controller,
    required this.session,
    required this.question,
    required this.round,
    required this.feedback,
  });

  final GameController controller;
  final LevelSession session;
  final Question question;
  final DragSpellRound round;
  final bool feedback;

  /// The picture of the asked item, when the level's hint mode allows it.
  ///
  /// Driven by [GameController.showPromptHint], which notifies only when the
  /// flag flips: the 60 Hz tick must not rebuild this picture.
  Widget? _hint() {
    final q = question;
    final id = q is SpellQuestion ? q.imageItemId : q.itemId;
    if (id == null || session.hintMode == HintMode.none) return null;
    final item = controller.itemFor(id);
    if (ItemPicture.assetFor(item) == null) return null;
    if (!controller.showPromptHint) return null;
    return Padding(
      padding: const EdgeInsets.only(right: 16),
      child: ItemPicture(
        key: const ValueKey('hint-picture'),
        item: item,
        size: 96,
        // Never the word: a screen reader would announce the answer.
        semanticLabel: 'Hình gợi ý',
      ),
    );
  }

  String get _answerText {
    final q = question;
    return q is SpellQuestion ? q.word : (q as OrderQuestion).answer.join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final result = session.lastResult;
    final spell = question is SpellQuestion;
    final hint = _hint();
    return LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          ?hint,
          const Icon(Icons.volume_up, size: 48, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: feedback
                ? Text(
                    key: const ValueKey('answer-reveal'),
                    _answerText,
                    style: AppTheme.textStyles.heading,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        spell ? 'Nghe và ghép chữ' : 'Nghe và sắp xếp câu',
                        style: t.bodyLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (box.maxHeight >= 70)
                        Text(
                          'Giữ tay trên ô 1 giây, hoặc chạm vào ô',
                          style: AppTheme.textStyles.play.copyWith(
                            color: AppTheme.muted,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
          ),
          if (!feedback && round.carrying != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Row(
                key: const ValueKey('carrying'),
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Đang cầm',
                    style: AppTheme.textStyles.play.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _MiniChip(text: round.carrying!),
                ],
              ),
            ),
          if (feedback) RoundVerdict(result: result),
          TinTin(
            state: RoundVerdict.mascotFor(result, feedback: feedback),
            size: box.maxHeight.clamp(56.0, 120.0),
            pulse: session.index,
          ),
        ],
      ),
    );
  }
}

/// One hold / tap target: a global key (hit testing) around a tappable child.
class _Target extends StatelessWidget {
  const _Target({
    required this.screen,
    required this.id,
    required this.child,
    this.tappable = true,
  });

  final _DragSpellScreenState screen;
  final String id;
  final Widget child;
  final bool tappable;

  @override
  Widget build(BuildContext context) {
    return KeyedSubtree(
      key: screen._keyFor(id),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: tappable ? () => screen._tap(id) : null,
        child: child,
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    super.key,
    required this.text,
    required this.semanticLabel,
    this.empty = false,
    this.hovered = false,
    this.faded = false,
    this.solid = false,
  });

  final String? text;
  final String semanticLabel;
  final bool empty;
  final bool hovered;
  final bool faded;
  final bool solid;

  @override
  Widget build(BuildContext context) {
    final border = hovered
        ? AppTheme.yellow
        : (empty ? AppTheme.muted : AppTheme.accent);
    return Semantics(
      label: semanticLabel,
      button: true,
      excludeSemantics: true,
      child: Opacity(
        opacity: faded ? 0.25 : 1,
        child: Container(
          constraints: const BoxConstraints(
            minHeight: AppTheme.minTarget,
            minWidth: AppTheme.minTarget,
          ),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: solid
                ? AppTheme.accent
                : (empty ? AppTheme.background : AppTheme.surface),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: border, width: hovered ? 6 : 4),
          ),
          child: text == null
              ? const SizedBox.shrink()
              : _TileText(
                  text: text!,
                  style: solid
                      ? AppTheme.textStyles.heading.copyWith(
                          color: AppTheme.background,
                        )
                      : AppTheme.textStyles.heading,
                ),
        ),
      ),
    );
  }
}

/// A tile's text at the largest size that fits its cell, and never below
/// [minTileFont]: a whole word shrunk to fit a letter-sized cell cannot be
/// read from 2-3 m, which is the only distance this game is played from.
///
/// The size is measured (so the device's real font metrics decide, not an
/// estimate); the floor is explicit, and in the worst case the word is
/// ellipsized instead of scaled below it. Cells are sized from the text too
/// ([_minCellWidth]), so the floor is a last resort, not the normal case.
class _TileText extends StatelessWidget {
  const _TileText({required this.text, required this.style});

  final String text;
  final TextStyle style;

  /// Smallest font a word tile may be drawn at.
  static const double minTileFont = 28;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final base = style.fontSize ?? minTileFont;
    return LayoutBuilder(
      builder: (context, box) {
        var size = base;
        if (box.hasBoundedWidth && base > minTileFont) {
          final tp = TextPainter(
            text: TextSpan(text: text, style: style),
            textDirection: TextDirection.ltr,
            maxLines: 1,
            textScaler: scaler,
          )..layout();
          final fitW = tp.width <= 0 ? 1.0 : box.maxWidth / tp.width;
          final fitH = (box.hasBoundedHeight && tp.height > 0)
              ? box.maxHeight / tp.height
              : 1.0;
          final fit = math.min(fitW, fitH);
          if (fit < 1) size = math.max(minTileFont, base * fit);
        }
        return Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(fontSize: size),
        );
      },
    );
  }
}

const double _cellGap = 10;
const double _rowGap = 8;

/// Width a cell needs so that the longest of [texts] can be drawn at
/// [_TileText.minTileFont]: about half an em per character plus the chip's
/// horizontal padding (2x6) and border (2x4). Never below the touch target.
///
/// Single letters (spelling) land on [AppTheme.minTarget] as before; whole
/// words (sentence ordering) make the cells wider and the rows fewer, which
/// the tray/slot flex factors already follow.
double _minCellWidth(List<String> texts) {
  var chars = 1;
  for (final t in texts) {
    if (t.length > chars) chars = t.length;
  }
  final w = 0.5 * _TileText.minTileFont * chars + 20;
  return w < AppTheme.minTarget ? AppTheme.minTarget : w;
}

/// Cells per row so that every cell is at least [minCell] wide in [width] px,
/// spread evenly over as many rows as that needs.
int _cellsPerRow(int n, double width, double minCell) {
  if (n <= 0) return 1;
  final fit = ((width + _cellGap) / (minCell + _cellGap)).floor().clamp(1, n);
  final rows = (n + fit - 1) ~/ fit;
  return (n + rows - 1) ~/ rows;
}

int _rowCount(int n, double width, double minCell) {
  final per = _cellsPerRow(n, width, minCell);
  return n <= 0 ? 1 : (n + per - 1) ~/ per;
}

/// Lays [n] cells in rows of [perRow] (the last row is padded with blanks).
Widget _wrapped(int n, int perRow, Widget Function(int i) cell) {
  Widget row(int from, int to) => Row(
    children: [
      for (var i = from; i < from + perRow; i++) ...[
        if (i > from) const SizedBox(width: _cellGap),
        Expanded(child: i < to ? cell(i) : const SizedBox.shrink()),
      ],
    ],
  );
  final rows = (n + perRow - 1) ~/ perRow;
  return Column(
    children: [
      for (var r = 0; r < rows; r++) ...[
        if (r > 0) const SizedBox(height: _rowGap),
        Expanded(child: row(r * perRow, math.min(n, (r + 1) * perRow))),
      ],
    ],
  );
}

class _Slots extends StatelessWidget {
  const _Slots({
    required this.screen,
    required this.round,
    required this.perRow,
  });

  final _DragSpellScreenState screen;
  final DragSpellRound round;
  final int perRow;

  @override
  Widget build(BuildContext context) {
    final slots = round.slots;
    final hover = screen._progress.targetId;
    return _wrapped(slots.length, perRow, (i) {
      return _Target(
        screen: screen,
        id: 'slot:$i',
        child: _Chip(
          key: ValueKey('slot-$i'),
          text: slots[i],
          empty: slots[i] == null,
          hovered: hover == 'slot:$i',
          semanticLabel: slots[i] == null
              ? 'Ô ${i + 1}, trống'
              : 'Ô ${i + 1}, ${slots[i]}',
        ),
      );
    });
  }
}

class _Tray extends StatelessWidget {
  const _Tray({
    required this.screen,
    required this.round,
    required this.perRow,
  });

  final _DragSpellScreenState screen;
  final DragSpellRound round;
  final int perRow;

  @override
  Widget build(BuildContext context) {
    final hover = screen._progress.targetId;
    return _wrapped(round.tiles.length, perRow, (i) {
      return _Target(
        screen: screen,
        id: 'tile:$i',
        tappable: !round.isTileUsed(i),
        child: _Chip(
          key: ValueKey('tile-$i'),
          text: round.tiles[i],
          solid: !round.isTileUsed(i),
          faded: round.isTileUsed(i),
          hovered: hover == 'tile:$i',
          semanticLabel: round.isTileUsed(i)
              ? 'Đã dùng, ${round.tiles[i]}'
              : round.tiles[i],
        ),
      );
    });
  }
}

class _CheckButton extends StatelessWidget {
  const _CheckButton({required this.screen, required this.enabled});

  final _DragSpellScreenState screen;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final hovered = screen._progress.targetId == 'check';
    return _Target(
      screen: screen,
      id: 'check',
      tappable: enabled,
      child: Semantics(
        label: enabled ? 'Kiểm tra' : 'Kiểm tra, điền đủ các ô trước',
        button: true,
        enabled: enabled,
        excludeSemantics: true,
        child: Container(
          key: const ValueKey('check-button'),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: enabled ? AppTheme.green : AppTheme.surface,
            borderRadius: BorderRadius.circular(28),
            border: Border.all(
              color: hovered ? AppTheme.yellow : Colors.transparent,
              width: 6,
            ),
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.check,
                    size: 36,
                    color: enabled ? AppTheme.background : AppTheme.muted,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Kiểm tra',
                    style: AppTheme.textStyles.label.copyWith(
                      color: enabled ? AppTheme.background : AppTheme.muted,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
