import 'package:flutter/material.dart';

import '../../app/game_controller.dart';
import '../../content/question_models.dart';
import '../../modes/yes_no.dart';
import '../../session/level_session.dart';
import '../kit/kit.dart';
import '../theme/app_theme.dart';
import 'lane_jump_screen.dart' show ItemPicture;
import 'play_header.dart';
import 'round_verdict.dart';

/// The yesNo play screen "Đúng hay Sai" (grades 3-5): a picture and a
/// statement about it; the child raises the LEFT hand for "Đúng" or the RIGHT
/// hand for "Sai". The two big targets below are also the touch fallback
/// ([GameController.answerYesNo]).
///
/// The statement is the question (shown and spoken), so it is not a leak.
/// Nothing says which side is right before the answer: the targets look and
/// read the same, and the right side is highlighted only after the result.
///
/// No animation is used, so reduce-motion needs no special case.
class YesNoScreen extends StatelessWidget {
  const YesNoScreen({super.key, required this.controller, this.onExit});

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
        if (round is! YesNoRound || q is! ChoiceQuestion) {
          return const SizedBox.shrink();
        }
        final answered = s.phase == SessionPhase.feedback;
        return SafeArea(
          child: LayoutBuilder(
            builder: (context, box) {
              final compact = box.maxHeight < 420;
              final gap = compact ? 6.0 : 12.0;
              final picture = _Picture(
                controller: controller,
                question: q,
                session: s,
                answered: answered,
              );
              final statement = _Statement(text: q.promptText ?? '');
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
                      child: compact
                          // Short screen: picture beside the statement.
                          ? Row(
                              children: [
                                AspectRatio(aspectRatio: 1, child: picture),
                                SizedBox(width: gap * 2),
                                Expanded(child: Center(child: statement)),
                              ],
                            )
                          : Column(
                              children: [
                                Expanded(child: Center(child: picture)),
                                SizedBox(height: gap),
                                statement,
                              ],
                            ),
                    ),
                    SizedBox(height: gap * 2),
                    SizedBox(
                      height: _targetHeight(
                        context,
                        compact,
                        (box.maxWidth - 48 - gap * 2) / 2,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: _AnswerTarget(
                              key: const ValueKey('yesno-yes'),
                              hintKey: const ValueKey('yesno-hint-left'),
                              label: 'Đúng',
                              hint: 'giơ tay trái',
                              base: AppTheme.accent,
                              index: 0,
                              session: s,
                              question: q,
                              round: round,
                              onTap: () => controller.answerYesNo(0),
                            ),
                          ),
                          SizedBox(width: gap * 2),
                          Expanded(
                            child: _AnswerTarget(
                              key: const ValueKey('yesno-no'),
                              hintKey: const ValueKey('yesno-hint-right'),
                              label: 'Sai',
                              hint: 'giơ tay phải',
                              base: AppTheme.orange,
                              index: 1,
                              session: s,
                              question: q,
                              round: round,
                              onTap: () => controller.answerYesNo(1),
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
        );
      },
    );
  }
}

/// Height of the answer targets: the label and hint at the current text
/// scale (the hint may wrap to a second line when [width] is short) plus
/// padding, never below the base height.
double _targetHeight(BuildContext context, bool compact, double width) {
  final scaler = MediaQuery.textScalerOf(context);
  final p = TextPainter(
    text: TextSpan(text: _hintWidest, style: AppTheme.textStyles.label),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout(maxWidth: width - 8);
  final hintLines = p.computeLineMetrics().length.clamp(1, 2);
  p.dispose();
  final text =
      (scaler.scale(28) + hintLines * scaler.scale(24)) * AppTheme.lineHeight +
      20;
  final base = compact ? 80.0 : 112.0;
  return text > base ? text : base;
}

const _hintWidest = 'giơ tay phải';

/// The pictured item in a sticker card. Silent for screen readers (the
/// statement names it); the verdict appears over it after the answer.
class _Picture extends StatelessWidget {
  const _Picture({
    required this.controller,
    required this.question,
    required this.session,
    required this.answered,
  });

  final GameController controller;
  final ChoiceQuestion question;
  final LevelSession session;
  final bool answered;

  @override
  Widget build(BuildContext context) {
    final id = question.promptImageItemId;
    return AspectRatio(
      aspectRatio: 1,
      child: Stack(
        key: const ValueKey('yesno-picture'),
        alignment: Alignment.bottomCenter,
        children: [
          Positioned.fill(
            child: StickerCard(
              child: id == null
                  ? const SizedBox.shrink()
                  : FittedBox(
                      fit: BoxFit.contain,
                      child: ItemPicture(item: controller.itemFor(id)),
                    ),
            ),
          ),
          if (answered)
            Positioned(
              bottom: 8,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppTheme.shade4d,
                  borderRadius: BorderRadius.circular(32),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: RoundVerdict(
                    result: session.lastResult,
                    iconSize: 36,
                    trailing: 0,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The statement as a prompt pill: play size, up to two lines, never scaled
/// down.
class _Statement extends StatelessWidget {
  const _Statement({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surfaceLight,
        borderRadius: BorderRadius.circular(32),
        boxShadow: const [BoxShadow(color: AppTheme.ink, offset: Offset(0, 5))],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Text(
          text,
          key: const ValueKey('yesno-statement'),
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: AppTheme.textStyles.play.copyWith(color: AppTheme.text),
        ),
      ),
    );
  }
}

/// One of the two big answer targets. Same look and same semantics shape on
/// both sides until the answer; then the right side turns green and a wrong
/// pick turns coral.
class _AnswerTarget extends StatelessWidget {
  const _AnswerTarget({
    super.key,
    required this.hintKey,
    required this.label,
    required this.hint,
    required this.base,
    required this.index,
    required this.session,
    required this.question,
    required this.round,
    required this.onTap,
  });

  final Key hintKey;
  final String label, hint;
  final Color base;
  final int index;
  final LevelSession session;
  final ChoiceQuestion question;
  final YesNoRound round;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final answered = session.phase == SessionPhase.feedback;
    final isRight = index == question.correctIndex;
    final wrongPick = answered && round.chosenIndex == index && !isRight;
    final fill = answered && isRight
        ? AppTheme.green
        : wrongPick
        ? AppTheme.coral
        : base;
    final enabled = !answered;
    return Semantics(
      button: true,
      enabled: enabled,
      // Same shape both sides; the truth is only visual and after the result.
      label: '$label, $hint',
      onTap: enabled ? onTap : null,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: Ink(
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(32),
            boxShadow: const [
              BoxShadow(color: AppTheme.ink, offset: Offset(0, 6)),
            ],
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(32),
            onTap: enabled ? onTap : null,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (answered && isRight) ...[
                        const Icon(Icons.check, size: 36, color: AppTheme.ink),
                        const SizedBox(width: 8),
                      ],
                      Text(
                        label,
                        style: AppTheme.textStyles.play.copyWith(
                          color: AppTheme.ink,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Text(
                    hint,
                    key: hintKey,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: AppTheme.textStyles.label.copyWith(
                      color: AppTheme.ink,
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
