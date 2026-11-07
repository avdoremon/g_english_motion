import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/game_controller.dart';
import '../../content/models.dart';
import '../../content/question_models.dart';
import '../../modes/hold_pick.dart';
import '../../session/level_session.dart';
import '../theme/app_theme.dart';
import 'hold_pick_frame.dart';
import 'lane_jump_screen.dart' show ItemPicture;
import 'play_header.dart';

/// The memoryFlip play screen (grades 2-5): a face-up picture and 3-5 word
/// cards. The cards are face-up for the peek, then turn face-down; the child
/// holds a hand on the card that matches the picture for a second (or taps it).
///
/// While the cards are face-down nothing on screen or in the semantics tree
/// names their words, and the prompt picture is silent: the answer is only
/// ever visible during the peek, as the mode intends, and after the result.
class MemoryFlipScreen extends StatelessWidget {
  const MemoryFlipScreen({
    super.key,
    required this.controller,
    this.onExit,
    this.clock,
  });

  final GameController controller;
  final VoidCallback? onExit;

  /// Monotonic clock of the cursor's freshness (injectable for tests).
  final Duration Function()? clock;

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
        // Read before the round starts: the words are face-up meanwhile.
        final prompting = s.phase == SessionPhase.prompting;
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
                          text: (prompting || st.peeking)
                              ? 'Nhớ các thẻ nhé!'
                              : 'Tìm thẻ cùng cặp',
                          picture: pictureId == null
                              ? null
                              : ItemPicture(
                                  key: const ValueKey('prompt-picture'),
                                  item: c.itemFor(pictureId),
                                  size: promptHeight - 12,
                                ),
                        ),
                        layout: (i, n, board) => _cardRect(i, n, board),
                        semanticLabel: (i, st) {
                          final word = c.itemFor(q.choices[i].itemId).word;
                          if (st.answered) {
                            return i == q.correctIndex ? '$word, đúng' : word;
                          }
                          if (prompting || st.peeking) return word;
                          // Face-down: the card's word stays secret.
                          return 'Thẻ ${i + 1}, đang úp';
                        },
                        itemBuilder: (context, i, size, st) => _Card(
                          item: c.itemFor(q.choices[i].itemId),
                          faceUp: prompting || st.peeking || st.answered,
                          hovered: st.hover == i,
                          correct: st.answered && i == q.correctIndex,
                          wrong:
                              st.answered &&
                              i == st.chosen &&
                              i != q.correctIndex,
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

  /// One row of cards, centred, with gaps between them.
  static Rect _cardRect(int i, int n, Size board) {
    const gap = 16.0;
    final w = math.min((board.width - gap * (n - 1)) / n, 200.0);
    final h = math.min(board.height, w * 1.25);
    final left = (board.width - (w * n + gap * (n - 1))) / 2;
    return Rect.fromLTWH(left + i * (w + gap), (board.height - h) / 2, w, h);
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.item,
    required this.faceUp,
    required this.hovered,
    required this.correct,
    required this.wrong,
    required this.instant,
  });

  final ContentItem item;
  final bool faceUp, hovered, correct, wrong, instant;

  @override
  Widget build(BuildContext context) {
    final border = correct
        ? AppTheme.green
        : wrong
        ? AppTheme.coral
        : hovered
        ? AppTheme.yellow
        : AppTheme.ink;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: faceUp ? 1 : 0),
      duration: instant ? Duration.zero : const Duration(milliseconds: 280),
      builder: (context, v, _) {
        // The word is in the tree only once the card is past the half turn.
        final showFace = v >= 0.5;
        final turn = Matrix4.identity()
          ..setEntry(3, 2, 0.001)
          ..rotateY(v * math.pi + (showFace ? math.pi : 0));
        return Transform(
          alignment: Alignment.center,
          transform: turn,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: showFace ? AppTheme.cardFill : AppTheme.purple,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: border, width: 5),
                    boxShadow: const [
                      BoxShadow(color: AppTheme.shadow, offset: Offset(0, 7)),
                    ],
                  ),
                  child: Center(
                    child: showFace
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                item.word,
                                maxLines: 1,
                                style: AppTheme.textStyles.heading.copyWith(
                                  color: AppTheme.ink,
                                ),
                              ),
                            ),
                          )
                        : const Icon(
                            Icons.star,
                            size: 44,
                            color: AppTheme.yellow,
                          ),
                  ),
                ),
              ),
              if (correct)
                const Positioned(
                  right: -10,
                  top: -10,
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
          ),
        );
      },
    );
  }
}
