import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/game_controller.dart';
import '../../content/question_models.dart';
import '../../modes/hold_pick.dart';
import '../../session/level_session.dart';
import '../theme/app_theme.dart';
import 'hold_pick_frame.dart';
import 'lane_jump_screen.dart' show ItemPicture;
import 'play_header.dart';

/// The balloonPop play screen (grades 3-5): the prompt is a picture, the
/// balloons carry look-alike words. The child holds a hand on the balloon
/// with the right word for 0.6 s to pop it (or taps it). Sweeping across a
/// balloon never pops it.
///
/// The balloons show their words by design; nothing (colour, size, semantics)
/// marks the right one before the result.
class BalloonPopScreen extends StatelessWidget {
  const BalloonPopScreen({
    super.key,
    required this.controller,
    this.onExit,
    this.clock,
  });

  final GameController controller;
  final VoidCallback? onExit;

  /// Monotonic clock of the cursor's freshness (injectable for tests).
  final Duration Function()? clock;

  static const _palette = [
    AppTheme.accent,
    AppTheme.yellow,
    AppTheme.coral,
    AppTheme.green,
    AppTheme.orange,
  ];

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.session;
        if (s == null || s.phase == SessionPhase.finished) {
          return const SizedBox.shrink();
        }
        final q = s.current.question;
        final round = s.round;
        if (round is! HoldPickRound || q is! ChoiceQuestion) {
          return const SizedBox.shrink();
        }
        final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
        return SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final compact = box.maxHeight < 420;
              final gap = compact ? 6.0 : 12.0;
              final promptHeight = compact ? 64.0 : 96.0;
              final pictureId = q.promptImageItemId;
              return Padding(
                padding: compact
                    ? const EdgeInsets.fromLTRB(24, 6, 24, 8)
                    : const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Column(
                  children: [
                    PlayHeader(controller: c, session: s, onExit: onExit),
                    SizedBox(height: gap),
                    Expanded(
                      child: HoldPickFrame(
                        controller: c,
                        round: round,
                        clock: clock,
                        promptHeight: promptHeight,
                        promptBuilder: (context, st) => HoldPromptRow(
                          height: promptHeight,
                          result: st.result,
                          pulse: s.index,
                          text: 'Chọc bóng có chữ đúng',
                          picture: pictureId == null
                              ? null
                              : ItemPicture(
                                  key: const ValueKey('prompt-picture'),
                                  item: c.itemFor(pictureId),
                                  size: promptHeight - 12,
                                ),
                        ),
                        layout: _balloonRect,
                        semanticLabel: (i, st) {
                          final word = c.itemFor(q.choices[i].itemId).word;
                          return st.answered && i == q.correctIndex
                              ? '$word, đúng'
                              : word;
                        },
                        itemBuilder: (context, i, size, st) => _Balloon(
                          word: c.itemFor(q.choices[i].itemId).word,
                          color: _palette[i % _palette.length],
                          hovered: st.hover == i,
                          popped: st.answered && i == st.chosen,
                          correct: st.answered && i == q.correctIndex,
                          instant: reduce,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );
  }

  /// A row of balloons with gaps between them, floating at slightly
  /// different heights when the board is taller than a balloon.
  static Rect _balloonRect(int i, int n, Size board) {
    const gap = 16.0;
    const float = [0.15, 0.7, 0.35, 0.85, 0.5];
    final w = math.min((board.width - gap * (n - 1)) / n, 160.0);
    final h = math.min(board.height, w * 1.5);
    final left = (board.width - (w * n + gap * (n - 1))) / 2;
    final top = (board.height - h) * float[i % float.length];
    return Rect.fromLTWH(left + i * (w + gap), top, w, h);
  }
}

class _Balloon extends StatelessWidget {
  const _Balloon({
    required this.word,
    required this.color,
    required this.hovered,
    required this.popped,
    required this.correct,
    required this.instant,
  });

  final String word;
  final Color color;
  final bool hovered, popped, correct, instant;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final tail = box.maxHeight * 0.18;
        final body = box.maxHeight - tail;
        final border = correct
            ? AppTheme.green
            : hovered
            ? AppTheme.yellow
            : AppTheme.ink;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned(
              left: 0,
              right: 0,
              top: 0,
              height: body,
              child: popped
                  ? TweenAnimationBuilder<double>(
                      tween: Tween(begin: instant ? 1 : 0.4, end: 1),
                      duration: instant
                          ? Duration.zero
                          : const Duration(milliseconds: 240),
                      builder: (context, v, child) =>
                          Transform.scale(scale: v, child: child),
                      child: Icon(
                        Icons.star,
                        key: const ValueKey('pop'),
                        size: math.min(body, box.maxWidth) * 0.8,
                        color: correct ? AppTheme.green : AppTheme.yellow,
                      ),
                    )
                  : DecoratedBox(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.elliptical(box.maxWidth / 2, body * 0.55),
                          bottom: Radius.elliptical(
                            box.maxWidth / 2,
                            body * 0.45,
                          ),
                        ),
                        border: Border.all(
                          color: border,
                          width: (hovered || correct) ? 5 : 4,
                        ),
                      ),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              word,
                              maxLines: 1,
                              style: AppTheme.textStyles.heading.copyWith(
                                color: AppTheme.ink,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            if (!popped)
              Positioned(
                left: box.maxWidth / 2 - 1.5,
                top: body,
                width: 3,
                height: tail,
                child: const ColoredBox(color: AppTheme.muted),
              ),
            if (correct)
              const Positioned(
                right: 0,
                top: 0,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppTheme.green,
                    shape: BoxShape.circle,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.check, size: 24, color: AppTheme.ink),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
