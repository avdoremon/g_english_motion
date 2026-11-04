import 'package:flutter/material.dart';

import '../../app/game_controller.dart';
import '../../content/models.dart';
import '../../content/question_models.dart';
import '../../input/game_input_event.dart';
import '../../input/pose_types.dart';
import '../../levels/level_config.dart';
import '../../modes/round.dart';
import '../../modes/sky_shoot.dart';
import '../../session/level_session.dart';
import '../mascot/tin_tin.dart';
import '../theme/app_theme.dart';
import 'lane_jump_screen.dart' show ItemPicture;
import 'play_header.dart';

/// The SkyShoot play screen (grades 3-5): answers drift in the sky, an arrow
/// sweeps along the bottom; jump (or raise both hands) to shoot, then pull
/// the rope with alternating hands to bring the hit answer down.
///
/// The field is drawn at [GameController.frameClock], the clock of the pose
/// frames, so the arrow the child sees is the one a shot is scored against.
///
/// Touch fallback (playable without a camera): a tap on the sky shoots, and
/// while reeling each tap is a pull with the other hand.
///
/// Nothing on screen marks the right answer before the child answered; the
/// hint pictures belong to all options alike.
class SkyShootScreen extends StatefulWidget {
  const SkyShootScreen({super.key, required this.controller, this.onExit});

  final GameController controller;
  final VoidCallback? onExit;

  @override
  State<SkyShootScreen> createState() => _SkyShootScreenState();
}

class _SkyShootScreenState extends State<SkyShootScreen> {
  Hand _nextTouchHand = Hand.left;

  void _tapSky(SkyShootRound round) {
    final at = widget.controller.frameClock;
    if (round.phase == SkyPhase.aiming) {
      // The round scores a shot at (at - castLatency), which is right for a
      // pose event (the child saw the arrow that long ago). A tap is on the
      // arrow the child sees now: add the latency back.
      widget.controller.touchInput(
        Confirmed(0, at: at + widget.controller.castLatency),
      );
    } else if (round.phase == SkyPhase.reeling) {
      final hand = _nextTouchHand;
      _nextTouchHand = hand == Hand.left ? Hand.right : Hand.left;
      widget.controller.touchInput(Pulled(hand, at: at));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final s = c.session;
        if (s == null || s.phase == SessionPhase.finished) {
          return const SizedBox.shrink();
        }
        final q = s.current.question;
        final round = s.round;
        if (round is! SkyShootRound || q is! ChoiceQuestion) {
          return const SizedBox.shrink();
        }
        final feedback = s.phase == SessionPhase.feedback;
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
                      controller: c,
                      session: s,
                      onExit: widget.onExit,
                    ),
                    SizedBox(height: gap),
                    SizedBox(
                      height: compact ? 64 : 96,
                      child: _StatusRow(
                        controller: c,
                        session: s,
                        question: q,
                        round: round,
                        feedback: feedback,
                      ),
                    ),
                    SizedBox(height: gap),
                    Expanded(
                      child: _Sky(
                        controller: c,
                        session: s,
                        question: q,
                        round: round,
                        feedback: feedback,
                        compact: compact,
                        onTap: () => _tapSky(round),
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

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.controller,
    required this.session,
    required this.question,
    required this.round,
    required this.feedback,
  });

  final GameController controller;
  final LevelSession session;
  final ChoiceQuestion question;
  final SkyShootRound round;
  final bool feedback;

  Widget? _hint() {
    final id = question.promptImageItemId;
    if (id == null || session.hintMode == HintMode.none) return null;
    return ListenableBuilder(
      listenable: controller.hudTick,
      builder: (context, _) {
        final show =
            session.hintMode == HintMode.full ||
            session.roundElapsedFraction >= LevelSession.partialHintAt;
        if (!show) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(right: 16),
          child: ItemPicture(
            key: const ValueKey('hint-picture'),
            item: controller.itemFor(id),
            size: 72,
            semanticLabel: 'Hình gợi ý',
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final ok = session.lastResult == RoundResult.correct;
    final timedOut = session.lastResult == RoundResult.timeout;
    final blank = question.form == QuestionForm.fillBlank;
    final hint = _hint();
    return LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          ?hint,
          const Icon(Icons.volume_up, size: 44, color: AppTheme.accent),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              blank ? (question.promptText ?? 'Nghe nhé') : 'Nghe nhé',
              key: const ValueKey('prompt'),
              style: t.titleLarge,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 12),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                label: 'Còn ${round.shotsLeft} lượt bắn',
                excludeSemantics: true,
                child: Row(
                  key: const ValueKey('shots-left'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < round.shots; i++)
                      Icon(
                        Icons.arrow_upward,
                        size: 28,
                        color: i < round.shotsLeft
                            ? AppTheme.accent
                            : AppTheme.surface,
                      ),
                    const SizedBox(width: 8),
                    Text('Lượt bắn: ${round.shotsLeft}', style: t.bodyMedium),
                  ],
                ),
              ),
              Semantics(
                label: 'Kéo dây ${round.pulls} trên ${round.pullsNeeded} lần',
                excludeSemantics: true,
                child: Text(
                  'Kéo dây: ${round.pulls}/${round.pullsNeeded}',
                  key: const ValueKey('pulls'),
                  style: t.bodyMedium,
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          if (feedback)
            Row(
              key: const ValueKey('feedback-label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ok
                      ? Icons.check_circle
                      : (timedOut ? Icons.hourglass_bottom : Icons.cancel),
                  size: 44,
                  color: ok
                      ? AppTheme.green
                      : (timedOut ? AppTheme.muted : AppTheme.pink),
                ),
                const SizedBox(width: 8),
                // A timeout is never "wrong": the child may not have understood.
                Text(
                  ok ? 'Đúng' : (timedOut ? 'Hết giờ' : 'Sai'),
                  style: t.titleLarge,
                ),
                const SizedBox(width: 12),
              ],
            ),
          TinTin(
            state: !feedback
                ? TinTinState.idle
                : (ok
                      ? TinTinState.happy
                      : (timedOut ? TinTinState.idle : TinTinState.sad)),
            size: box.maxHeight.clamp(56.0, 100.0),
            pulse: session.index,
          ),
        ],
      ),
    );
  }
}

class _Sky extends StatelessWidget {
  const _Sky({
    required this.controller,
    required this.session,
    required this.question,
    required this.round,
    required this.feedback,
    required this.compact,
    required this.onTap,
  });

  final GameController controller;
  final LevelSession session;
  final ChoiceQuestion question;
  final SkyShootRound round;
  final bool feedback;
  final bool compact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ok = session.lastResult == RoundResult.correct;
    return Semantics(
      label: round.phase == SkyPhase.reeling
          ? 'Chạm để kéo dây'
          : 'Chạm để bắn mũi tên',
      button: true,
      child: GestureDetector(
        key: const ValueKey('sky'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppTheme.surface, AppTheme.background],
              ),
            ),
            child: Stack(
              children: [
                // The field follows the pose clock at the controller's tick.
                Positioned.fill(
                  child: ListenableBuilder(
                    listenable: controller.hudTick,
                    builder: (context, _) => _Field(
                      controller: controller,
                      session: session,
                      question: question,
                      round: round,
                      feedback: feedback,
                      compact: compact,
                    ),
                  ),
                ),
                if (feedback && ok)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Center(
                        child: Row(
                          key: const ValueKey('celebration'),
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.star,
                              size: 56,
                              color: AppTheme.yellow,
                            ),
                            TinTin(
                              state: TinTinState.dance,
                              size: compact ? 96 : 150,
                              pulse: session.index,
                            ),
                            const Icon(
                              Icons.star,
                              size: 56,
                              color: AppTheme.yellow,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.session,
    required this.question,
    required this.round,
    required this.feedback,
    required this.compact,
  });

  final GameController controller;
  final LevelSession session;
  final ChoiceQuestion question;
  final SkyShootRound round;
  final bool feedback;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final now = controller.frameClock;
    final hint = controller.showTileHints;
    final wrongReveal = feedback && session.lastResult != RoundResult.correct;
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth, h = box.maxHeight;
        final arrowZone = compact ? 52.0 : 72.0;
        final cardH = ((h - arrowZone) / 1.4).clamp(40.0, 96.0);
        final cardW = (w * 0.15).clamp(80.0, 200.0);
        final reel = round.pullsNeeded == 0
            ? 1.0
            : (round.pulls / round.pullsNeeded).clamp(0.0, 1.0);
        final hitIdx = round.hitIndex;
        final skyBottom = h - arrowZone;

        double cardTop(int i) {
          final base = (i % 2) * cardH * 0.35 + 4;
          if (i != hitIdx) return base;
          // The hooked answer comes down as the rope is pulled in.
          final target = skyBottom - cardH;
          return base + (target - base).clamp(0.0, double.infinity) * reel;
        }

        double cardX(int i) =>
            (i == hitIdx ? round.hitX : null) ?? round.field.answerX(i, now);

        final shot = round.phase == SkyPhase.aiming
            ? round.field.arrowX(now)
            : (round.hitX ?? round.field.arrowX(now));
        return Stack(
          children: [
            if (hitIdx != null)
              Positioned.fill(
                child: CustomPaint(
                  painter: _RopePainter(
                    fromX: shot * w,
                    fromY: h - arrowZone / 2,
                    toX: cardX(hitIdx) * w,
                    toY: cardTop(hitIdx) + cardH,
                  ),
                ),
              ),
            for (var i = 0; i < question.choices.length; i++)
              Positioned(
                left: cardX(i) * w - cardW / 2,
                top: cardTop(i),
                width: cardW,
                height: cardH,
                child: _AnswerCard(
                  key: ValueKey('answer-$i'),
                  option: question.choices[i],
                  word: controller.itemFor(question.choices[i].itemId).word,
                  hit: i == hitIdx,
                  isAnswer: wrongReveal && i == question.correctIndex,
                  pictureOf: hint
                      ? controller.itemFor(question.choices[i].itemId)
                      : null,
                ),
              ),
            Positioned(
              left: shot * w - 28,
              bottom: 4,
              width: 56,
              height: arrowZone - 8,
              child: Semantics(
                label: 'Mũi tên',
                excludeSemantics: true,
                child: Icon(
                  Icons.navigation,
                  key: const ValueKey('arrow'),
                  size: arrowZone - 12,
                  color: round.phase == SkyPhase.aiming
                      ? AppTheme.yellow
                      : AppTheme.accent,
                ),
              ),
            ),
            if (round.phase == SkyPhase.aiming && round.shotsLeft < round.shots)
              Positioned(
                left: 16,
                bottom: 8,
                child: Text(
                  'Trượt rồi! Bắn lại nhé',
                  key: const ValueKey('miss-note'),
                  style: t.bodyMedium,
                ),
              ),
            if (round.phase == SkyPhase.aiming &&
                round.shotsLeft == round.shots)
              Positioned(
                right: 16,
                bottom: 8,
                child: Text(
                  'Nhảy để bắn, hoặc chạm vào màn hình',
                  style: t.bodyMedium,
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AnswerCard extends StatelessWidget {
  const _AnswerCard({
    super.key,
    required this.option,
    required this.word,
    required this.hit,
    required this.isAnswer,
    this.pictureOf,
  });

  final ChoiceOption option;
  final String word;
  final bool hit;
  final bool isAnswer;

  /// Hint: the option's picture above its word (same flag for every card).
  final ContentItem? pictureOf;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final item = pictureOf;
    final showPic = item != null && ItemPicture.assetFor(item) != null;
    return Semantics(
      label: hit ? '$word, đang kéo' : word,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: hit ? const Color(0xFF3A36A0) : AppTheme.surface,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: hit ? AppTheme.yellow : AppTheme.accent,
            width: hit ? 6 : 3,
          ),
        ),
        child: Stack(
          children: [
            if (isAnswer)
              const Positioned(
                top: 0,
                right: 0,
                child: Icon(
                  Icons.check_circle,
                  size: 32,
                  color: AppTheme.green,
                ),
              ),
            Center(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (showPic) ...[
                      ItemPicture(item: item, size: 40),
                      const SizedBox(width: 6),
                    ],
                    Text(word, maxLines: 1, style: t.titleLarge),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RopePainter extends CustomPainter {
  const _RopePainter({
    required this.fromX,
    required this.fromY,
    required this.toX,
    required this.toY,
  });

  final double fromX, fromY, toX, toY;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(fromX, fromY),
      Offset(toX, toY),
      Paint()
        ..color = AppTheme.yellow
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_RopePainter old) =>
      fromX != old.fromX ||
      fromY != old.fromY ||
      toX != old.toX ||
      toY != old.toY;
}
