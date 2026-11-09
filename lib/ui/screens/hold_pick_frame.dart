import 'dart:async';

import 'package:flutter/material.dart';

import '../../app/game_controller.dart';
import '../../input/game_input_event.dart';
import '../../modes/hold_pick.dart';
import '../../modes/round.dart';
import '../mascot/tin_tin.dart';
import '../shell/hold_ring.dart';
import '../theme/app_theme.dart';
import 'round_verdict.dart';

final Stopwatch _sw = Stopwatch()..start();
Duration _monotonic() => _sw.elapsed;

/// What the item builders of a [HoldPickFrame] need to know of the round.
class HoldFrameState {
  const HoldFrameState({
    required this.peeking,
    required this.hover,
    required this.progress,
    required this.result,
    required this.chosen,
  });

  /// memoryFlip: the choices are still face-up for the peek.
  final bool peeking;

  /// Choice under the hand cursor (null: none).
  final int? hover;

  /// 0..1 progress of the current hold.
  final double progress;

  /// The round's result, null while it is being played.
  final RoundResult? result;
  final int? chosen;

  bool get answered => result != null;

  @override
  bool operator ==(Object other) =>
      other is HoldFrameState &&
      other.peeking == peeking &&
      other.hover == hover &&
      other.progress == progress &&
      other.result == result &&
      other.chosen == chosen;

  @override
  int get hashCode => Object.hash(peeking, hover, progress, result, chosen);
}

/// The playing area shared by memoryFlip and balloonPop: a prompt row above
/// a board of tappable targets with the hand cursor ([HoldRing]) on top.
///
/// - Reports the real target layout to the controller
///   ([GameController.setHoldLayout], normalised to the board), so a hold by
///   the hand cursor is graded against what is drawn.
/// - Follows the controller's 60 Hz tick (cursor events never notify, the end
///   of the peek is not notified either) and rebuilds only when the cursor,
///   the hold or the round's state changed.
/// - A tap on target `i` is `holdTarget('choice:<i>')`.
class HoldPickFrame extends StatefulWidget {
  const HoldPickFrame({
    super.key,
    required this.controller,
    required this.round,
    required this.promptHeight,
    required this.promptBuilder,
    required this.layout,
    required this.itemBuilder,
    required this.semanticLabel,
    this.clock,
  });

  /// No cursor update for this long: the hand is gone.
  static const cursorStale = Duration(milliseconds: 400);

  final GameController controller;
  final HoldPickRound round;
  final double promptHeight;
  final Widget Function(BuildContext context, HoldFrameState state)
  promptBuilder;

  /// Pixel rect of target [i] of [n] inside a board of [board] size.
  final Rect Function(int i, int n, Size board) layout;
  final Widget Function(
    BuildContext context,
    int i,
    Size size,
    HoldFrameState state,
  )
  itemBuilder;

  /// Screen-reader label of target [i] (never marks the right one early).
  final String Function(int i, HoldFrameState state) semanticLabel;

  /// Monotonic clock of the cursor's freshness (injectable for tests).
  final Duration Function()? clock;

  @override
  State<HoldPickFrame> createState() => _HoldPickFrameState();
}

class _HoldPickFrameState extends State<HoldPickFrame> {
  StreamSubscription<GameInputEvent>? _sub;
  Offset? _cursor;
  Duration _cursorAt = Duration.zero;
  Offset? _shown;
  HoldFrameState? _last;
  HoldPickRound? _round;
  Rect Function(int)? _layoutFn;

  Duration _now() => (widget.clock ?? _monotonic)();

  @override
  void initState() {
    super.initState();
    _sub = widget.controller.events.listen(_onEvent);
    widget.controller.hudTick.addListener(_tick);
  }

  @override
  void didUpdateWidget(HoldPickFrame old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      _sub?.cancel();
      old.controller.hudTick.removeListener(_tick);
      final fn = _layoutFn;
      if (fn != null) old.controller.clearHoldLayout(fn);
      _sub = widget.controller.events.listen(_onEvent);
      widget.controller.hudTick.addListener(_tick);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    widget.controller.hudTick.removeListener(_tick);
    // Never laid out: nothing of ours to clear (null would wipe a successor's).
    final fn = _layoutFn;
    if (fn != null) widget.controller.clearHoldLayout(fn);
    super.dispose();
  }

  void _onEvent(GameInputEvent e) {
    if (e is CursorMoved) {
      _cursor = Offset(e.x, e.y);
      _cursorAt = _now();
    }
  }

  HoldFrameState _state() {
    final r = widget.round;
    return HoldFrameState(
      peeking: r.peeking,
      hover: r.hoverIndex,
      progress: r.hoverIndex == null ? 0 : r.holdProgress,
      result: r.result,
      chosen: r.chosenIndex,
    );
  }

  Offset? _visibleCursor() {
    final c = _cursor;
    if (c == null || !widget.round.clockRunning) return null;
    return _now() - _cursorAt <= HoldPickFrame.cursorStale ? c : null;
  }

  void _tick() {
    if (!mounted) return;
    final s = _state();
    final c = _visibleCursor();
    if (s == _last && c == _shown) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (!identical(_round, widget.round)) {
      _round = widget.round;
      _cursor = null;
    }
    final st = _state();
    final cursor = _visibleCursor();
    _last = st;
    _shown = cursor;
    final n = widget.round.question.choices.length;
    return Column(
      children: [
        SizedBox(
          height: widget.promptHeight,
          child: widget.promptBuilder(context, st),
        ),
        const SizedBox(height: 8),
        Expanded(
          child: LayoutBuilder(
            builder: (context, box) {
              final board = box.biggest;
              final rects = [
                for (var i = 0; i < n; i++) widget.layout(i, n, board),
              ];
              // Lazily read by the round: the hold is graded on this layout.
              _layoutFn = (i) => i < 0 || i >= rects.length
                  ? Rect.zero
                  : Rect.fromLTRB(
                      rects[i].left / board.width,
                      rects[i].top / board.height,
                      rects[i].right / board.width,
                      rects[i].bottom / board.height,
                    );
              widget.controller.setHoldLayout(_layoutFn!);
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  for (var i = 0; i < n; i++)
                    Positioned.fromRect(
                      rect: rects[i],
                      child: Semantics(
                        button: true,
                        label: widget.semanticLabel(i, st),
                        excludeSemantics: true,
                        onTap: () => widget.controller.holdTarget('choice:$i'),
                        child: GestureDetector(
                          key: ValueKey('choice-$i'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () =>
                              widget.controller.holdTarget('choice:$i'),
                          child: widget.itemBuilder(
                            context,
                            i,
                            rects[i].size,
                            st,
                          ),
                        ),
                      ),
                    ),
                  if (cursor != null)
                    Positioned(
                      key: const ValueKey('hand-cursor'),
                      left: cursor.dx * board.width - 28,
                      top: cursor.dy * board.height - 28,
                      child: HoldRing(progress: st.progress),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The prompt row of the hold-to-pick screens: the prompt picture in a white
/// card, one line of instruction and, once answered, the verdict and Tin Tin.
class HoldPromptRow extends StatelessWidget {
  const HoldPromptRow({
    super.key,
    required this.picture,
    required this.text,
    required this.result,
    required this.pulse,
    required this.height,
  });

  /// The prompt picture (silent for screen readers: it names no word).
  final Widget? picture;
  final String text;
  final RoundResult? result;
  final int pulse;
  final double height;

  @override
  Widget build(BuildContext context) {
    final answered = result != null;
    return Row(
      children: [
        if (picture != null) ...[
          DecoratedBox(
            key: const ValueKey('prompt-card'),
            decoration: BoxDecoration(
              color: AppTheme.cardFill,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.ink, width: 3),
            ),
            child: Padding(padding: const EdgeInsets.all(3), child: picture),
          ),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: Align(
            alignment: Alignment.centerLeft,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.shade40,
                borderRadius: BorderRadius.circular(height / 2),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 6,
                ),
                child: Text(
                  text,
                  key: const ValueKey('prompt'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.textStyles.play,
                ),
              ),
            ),
          ),
        ),
        if (answered) RoundVerdict(result: result, iconSize: 36, trailing: 12),
        TinTin(
          state: RoundVerdict.mascotFor(result, feedback: answered),
          size: height.clamp(56.0, 96.0),
          pulse: pulse,
        ),
      ],
    );
  }
}
