import 'package:flutter/material.dart';

import '../../app/game_controller.dart';
import '../../content/question_models.dart';
import '../../input/action_detector.dart';
import '../../modes/action_round.dart';
import '../../modes/round.dart';
import '../../session/level_session.dart';
import '../mascot/tin_tin.dart';
import '../theme/app_theme.dart';
import 'play_header.dart';
import 'round_verdict.dart';

/// The puppySays play screen "Theo Pup" (grades 1-2): Space Puppy names a body
/// action, the child does it in front of the camera. There is no touch answer
/// and no camera image anywhere on this screen.
///
/// The command IS the instruction, so it is shown (and spoken) with a
/// pictogram of the action; nothing is hidden before the answer. A timeout is
/// neutral: "Hết giờ" and the Vietnamese hint, never "Sai", because the most
/// likely cause is an action the pose layer did not recognise.
///
/// Reduce-motion is handled by the mascot ([TinTin]); the countdown bar only
/// follows the round clock.
class PuppySaysScreen extends StatelessWidget {
  const PuppySaysScreen({super.key, required this.controller, this.onExit});

  final GameController controller;
  final VoidCallback? onExit;

  /// Material icon of each action (no bundled art).
  static IconData iconFor(PuppyAction a) => switch (a) {
    PuppyAction.jump => Icons.keyboard_double_arrow_up,
    PuppyAction.handsUp => Icons.back_hand,
    PuppyAction.clap => Icons.sign_language,
    PuppyAction.squat => Icons.keyboard_double_arrow_down,
  };

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
        if (s.round is! ActionRound || q is! ActionQuestion) {
          return const SizedBox.shrink();
        }
        final answered = s.phase == SessionPhase.feedback;
        return SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final compact = box.maxHeight < 420;
              final gap = compact ? 6.0 : 12.0;
              final result = s.lastResult;
              final timeout = answered && RoundVerdict.isTimeout(result);
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
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, area) {
                          final pup = (compact ? 170.0 : 260.0).clamp(
                            64.0,
                            area.maxHeight,
                          );
                          return Row(
                            children: [
                              Center(
                                child: TinTin(
                                  key: const ValueKey('puppy-mascot'),
                                  state: RoundVerdict.mascotFor(
                                    result,
                                    feedback: answered,
                                  ),
                                  size: pup,
                                  pulse: s.index,
                                ),
                              ),
                              SizedBox(width: gap * 2),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    if (compact && timeout)
                                      // Short screen, timeout: the two-line
                                      // verdict (kind line + hint, which names
                                      // the action) takes the command's room.
                                      const SizedBox.shrink()
                                    else if (compact)
                                      // Short screen: the pictogram sits
                                      // beside the command.
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          _Pictogram(
                                            action: q.action,
                                            size: 64,
                                          ),
                                          SizedBox(width: gap * 2),
                                          Flexible(
                                            child: _CommandPill(question: q),
                                          ),
                                        ],
                                      )
                                    else ...[
                                      _CommandPill(question: q),
                                      SizedBox(height: gap),
                                      _Pictogram(action: q.action, size: 120),
                                    ],
                                    // On a timeout the verdict (two lines) needs
                                    // the countdown's room; the clock is over.
                                    if (!timeout) ...[
                                      SizedBox(height: gap),
                                      _Countdown(controller: controller),
                                    ],
                                    SizedBox(height: gap),
                                    _VerdictSlot(
                                      visible: answered,
                                      result: result,
                                      hint: q.hintVi,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        },
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

/// The command as a prompt pill: heading size, up to two lines, never scaled
/// down. One semantics node that also tells the child what to do.
class _CommandPill extends StatelessWidget {
  const _CommandPill({required this.question});

  final ActionQuestion question;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      key: const ValueKey('puppy-command-semantics'),
      label: 'Pup nói: ${question.command}. ${question.hintVi}',
      excludeSemantics: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.surfaceLight,
          borderRadius: BorderRadius.circular(32),
          boxShadow: const [
            BoxShadow(color: AppTheme.ink, offset: Offset(0, 5)),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Text(
            question.command,
            key: const ValueKey('puppy-command'),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.textStyles.heading.copyWith(color: AppTheme.text),
          ),
        ),
      ),
    );
  }
}

/// The action as a Material icon in a round sticker. Decorative: the command
/// semantics already names the action.
class _Pictogram extends StatelessWidget {
  const _Pictogram({required this.action, required this.size});

  final PuppyAction action;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: DecoratedBox(
        key: const ValueKey('puppy-pictogram'),
        decoration: BoxDecoration(
          color: AppTheme.yellow,
          shape: BoxShape.circle,
          boxShadow: const [
            BoxShadow(color: AppTheme.ink, offset: Offset(0, 5)),
          ],
        ),
        child: SizedBox(
          width: size,
          height: size,
          child: Icon(
            PuppySaysScreen.iconFor(action),
            size: size * 0.65,
            color: AppTheme.ink,
          ),
        ),
      ),
    );
  }
}

/// Time left as a bar that only drains (no red, no alarm).
class _Countdown extends StatelessWidget {
  const _Countdown({required this.controller});

  final GameController controller;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ListenableBuilder(
        listenable: controller.hudTick,
        builder: (context, _) {
          final round = controller.session!.round;
          final limit = round.timeLimit.inMilliseconds;
          final frac = limit == 0
              ? 0.0
              : (round.remaining.inMilliseconds / limit).clamp(0.0, 1.0);
          return DecoratedBox(
            key: const ValueKey('puppy-countdown'),
            decoration: BoxDecoration(
              color: AppTheme.trackWhite,
              borderRadius: BorderRadius.circular(8),
            ),
            child: SizedBox(
              height: 16,
              width: double.infinity,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: frac,
                  heightFactor: 1,
                  child: DecoratedBox(
                    key: const ValueKey('puppy-countdown-fill'),
                    decoration: BoxDecoration(
                      color: AppTheme.accent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// The verdict ("Giỏi lắm!" / "Hết giờ" + hint). Before the result only an
/// empty box of the verdict's height is kept, so nothing jumps when it
/// appears (and no verdict text exists in the tree before it is true).
class _VerdictSlot extends StatelessWidget {
  const _VerdictSlot({
    required this.visible,
    required this.result,
    required this.hint,
  });

  final bool visible;
  final RoundResult? result;
  final String hint;

  @override
  Widget build(BuildContext context) {
    if (!visible) {
      final scaler = MediaQuery.textScalerOf(context);
      return SizedBox(
        height:
            scaler.scale(AppTheme.textStyles.heading.fontSize!) *
            AppTheme.lineHeight,
      );
    }
    final timeout = RoundVerdict.isTimeout(result);
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.shade4d,
          borderRadius: BorderRadius.circular(32),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            children: [
              RoundVerdict(
                result: result,
                iconSize: 36,
                trailing: 0,
                correctLabel: 'Giỏi lắm!',
              ),
              if (timeout)
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      ActionQuestion.notSeenVi,
                      key: const ValueKey('puppy-notseen'),
                      textAlign: TextAlign.center,
                      style: AppTheme.textStyles.play.copyWith(
                        color: AppTheme.text,
                      ),
                    ),
                    Text(
                      hint,
                      key: const ValueKey('puppy-hint'),
                      textAlign: TextAlign.center,
                      style: AppTheme.textStyles.play.copyWith(
                        color: AppTheme.text,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}
