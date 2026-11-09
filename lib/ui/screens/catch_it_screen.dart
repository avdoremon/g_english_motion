import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/game_controller.dart';
import '../../content/question_models.dart';
import '../../modes/catch_it.dart';
import '../../session/level_session.dart';
import '../mascot/tin_tin.dart';
import '../shell/hold_ring.dart';
import '../theme/app_theme.dart';
import 'lane_jump_screen.dart' show ItemPicture, QuestionPrompt;
import 'play_header.dart';
import 'round_verdict.dart';

/// The catchIt play screen "Hứng hình" (grades 1-2): three pictures fall in
/// three lanes over the round's time limit; the spoken word names one. The
/// child leans left/right to stand under it, and the picture in the child's
/// lane when they reach the catch line is the answer.
///
/// There is no touch input at all (like LaneJump): the lanes are not tappable,
/// the round is graded by the catch line only.
///
/// The player (Tin Tin) and the highlighted lane both come from one source,
/// [CatchItRound.lane] (kept in sync with the tracked lane by the controller).
/// The fall follows [CatchItRound.fallFraction], so it stands still whenever
/// the clock does (player lost, paused). With reduce-motion the pictures stay
/// in place and a countdown ring shows the time instead.
///
/// The prompt is the speaker icon and "Nghe nhé" only: the word, and any
/// semantics label naming a picture, appear after the result, never before.
class CatchItScreen extends StatelessWidget {
  const CatchItScreen({super.key, required this.controller, this.onExit});

  final GameController controller;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.session;
        if (s == null || s.phase == SessionPhase.finished) {
          return const SizedBox.shrink();
        }
        final q = s.current.question;
        final round = s.round;
        if (round is! CatchItRound || q is! ChoiceQuestion) {
          return const SizedBox.shrink();
        }
        return SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final compact = box.maxHeight < 420;
              final gap = compact ? 6.0 : 12.0;
              return Padding(
                padding: compact
                    ? const EdgeInsets.fromLTRB(24, 6, 24, 8)
                    : const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Column(
                  children: [
                    PlayHeader(
                      controller: controller,
                      session: s,
                      onExit: onExit,
                    ),
                    SizedBox(height: gap),
                    _Prompt(
                      controller: controller,
                      session: s,
                      question: q,
                      height: compact ? 56.0 : 72.0,
                    ),
                    SizedBox(height: gap),
                    Expanded(
                      child: _Field(
                        controller: controller,
                        round: round,
                        question: q,
                        pulse: s.index,
                        answered: s.phase == SessionPhase.feedback,
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
}

class _Prompt extends StatelessWidget {
  const _Prompt({
    required this.controller,
    required this.session,
    required this.question,
    required this.height,
  });

  final GameController controller;
  final LevelSession session;
  final ChoiceQuestion question;
  final double height;

  @override
  Widget build(BuildContext context) {
    final feedback = session.phase == SessionPhase.feedback;
    return SizedBox(
      height: height,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: QuestionPrompt(
                question: question,
                itemFor: controller.itemFor,
                feedback: feedback,
              ),
            ),
          ),
          if (feedback) ...[
            const SizedBox(width: 16),
            RoundVerdict(result: session.lastResult, iconSize: 48, trailing: 0),
          ],
        ],
      ),
    );
  }
}

/// The three lanes, the falling pictures and the player.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.round,
    required this.question,
    required this.pulse,
    required this.answered,
  });

  final GameController controller;
  final CatchItRound round;
  final ChoiceQuestion question;
  final int pulse;
  final bool answered;

  static const laneGap = 12.0;

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final n = question.choices.length;
    return LayoutBuilder(
      builder: (context, box) {
        final laneW = (box.maxWidth - laneGap * (n - 1)) / n;
        final player = (box.maxHeight * 0.3).clamp(56.0, 96.0);
        final sticker = math
            .min(laneW * 0.7, box.maxHeight * 0.32)
            .clamp(56.0, 112.0);
        final travel = math.max(0.0, box.maxHeight - player - sticker);
        double laneLeft(int i) => i * (laneW + laneGap);
        final result = round.result;
        return Stack(
          clipBehavior: Clip.hardEdge,
          children: [
            for (var i = 0; i < n; i++)
              Positioned(
                left: laneLeft(i),
                top: 0,
                width: laneW,
                height: box.maxHeight,
                child: _LaneBackdrop(
                  key: ValueKey('catch-lane-$i'),
                  selected: i == round.lane,
                ),
              ),
            // The pictures follow the round's clock; only they rebuild with
            // the 60 Hz tick.
            ListenableBuilder(
              listenable: controller.hudTick,
              builder: (context, _) {
                final fall = result != null
                    ? 1.0
                    : reduce
                    ? 0.5
                    : round.fallFraction;
                return Stack(
                  children: [
                    for (var i = 0; i < n; i++)
                      Positioned(
                        left: laneLeft(i) + (laneW - sticker) / 2,
                        top: fall * travel,
                        width: sticker,
                        height: sticker,
                        child: _FallingPicture(
                          key: ValueKey('catch-pic-$i'),
                          controller: controller,
                          question: question,
                          index: i,
                          chosen: round.chosenIndex,
                          answered: answered,
                        ),
                      ),
                    if (reduce && result == null)
                      Positioned(
                        left: laneLeft(0) + 8,
                        top: 8,
                        child: Semantics(
                          label:
                              'Còn ${(round.remaining.inMilliseconds / 1000).ceil()} giây',
                          child: HoldRing(
                            key: const ValueKey('catch-countdown'),
                            progress: round.fallFraction,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            // The catch line.
            Positioned(
              left: 0,
              right: 0,
              bottom: player - 2,
              height: 4,
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.yellow,
                  borderRadius: BorderRadius.all(Radius.circular(2)),
                ),
              ),
            ),
            AnimatedPositioned(
              key: const ValueKey('catch-player-pos'),
              duration: reduce
                  ? Duration.zero
                  : const Duration(milliseconds: 150),
              curve: Curves.easeOut,
              left: laneLeft(round.lane) + (laneW - player) / 2,
              bottom: 0,
              width: player,
              height: player,
              child: TinTin(
                key: const ValueKey('catch-player'),
                state: RoundVerdict.mascotFor(result, feedback: answered),
                size: player,
                pulse: pulse,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _LaneBackdrop extends StatelessWidget {
  const _LaneBackdrop({super.key, required this.selected});

  final bool selected;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected ? AppTheme.selectedFill : AppTheme.shade38,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: selected ? AppTheme.accent : AppTheme.trackWhite,
          width: selected ? 6 : 3,
        ),
      ),
    );
  }
}

class _FallingPicture extends StatelessWidget {
  const _FallingPicture({
    super.key,
    required this.controller,
    required this.question,
    required this.index,
    required this.chosen,
    required this.answered,
  });

  final GameController controller;
  final ChoiceQuestion question;
  final int index;
  final int? chosen;
  final bool answered;

  @override
  Widget build(BuildContext context) {
    final item = controller.itemFor(question.choices[index].itemId);
    final correct = answered && index == question.correctIndex;
    final wrong = answered && index == chosen && index != question.correctIndex;
    final border = correct
        ? AppTheme.green
        : wrong
        ? AppTheme.coral
        : AppTheme.ink;
    return Semantics(
      // Never the word before the result: it is the answer.
      label: answered ? item.word : 'Hình ${index + 1}',
      excludeSemantics: true,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.cardFill,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: border, width: 5),
                boxShadow: const [
                  BoxShadow(color: AppTheme.shadow, offset: Offset(0, 5)),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: FittedBox(
                  fit: BoxFit.contain,
                  child: ItemPicture(item: item, size: 100),
                ),
              ),
            ),
          ),
          if (correct)
            const Positioned(
              right: -8,
              top: -8,
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
  }
}
