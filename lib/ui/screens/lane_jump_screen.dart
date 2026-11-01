import 'package:flutter/material.dart';

import '../../app/game_controller.dart';
import '../../content/models.dart';
import '../../content/question_models.dart';
import '../../levels/scoring.dart';
import '../../modes/round.dart';
import '../../session/level_session.dart';
import '../mascot/tin_tin.dart';
import '../theme/app_theme.dart';

/// The LaneJump play screen (Space Cadets, canvas B "Lane"): header (level,
/// progress, timer ring, score), the prompt, one lane per choice and Tin Tin
/// with the Đúng/Sai verdict.
///
/// Pictures: the bundled PNG (`assets/images/<item.image>`) is drawn by
/// [ItemPicture]; when the item has no image or the asset cannot be loaded it
/// falls back to a coloured circle with the first letter of the word.
///
/// Prompt ([QuestionPrompt]): the listen forms show only the speaker icon and
/// "Nghe nhé" (a visible word would give the answer away; listen-and-pick-
/// picture reveals the word in the feedback, after answering); see-picture
/// shows the picture.
class LaneJumpScreen extends StatelessWidget {
  const LaneJumpScreen({super.key, required this.controller, this.onExit});

  final GameController controller;

  /// Optional exit button at the start of the header (the app leaves the
  /// play flow).
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
        if (q is! ChoiceQuestion) return const SizedBox.shrink();
        return _Body(
          controller: controller,
          session: s,
          question: q,
          onExit: onExit,
        );
      },
    );
  }
}

class _Body extends StatelessWidget {
  const _Body({
    required this.controller,
    required this.session,
    required this.question,
    this.onExit,
  });

  final GameController controller;
  final LevelSession session;
  final ChoiceQuestion question;
  final VoidCallback? onExit;

  bool get _feedback => session.phase == SessionPhase.feedback;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(
          children: [
            _Header(controller: controller, session: session, onExit: onExit),
            const SizedBox(height: 12),
            Expanded(flex: 3, child: _PromptArea(body: this)),
            const SizedBox(height: 12),
            Expanded(flex: 5, child: _Lanes(body: this)),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.controller, required this.session, this.onExit});

  final GameController controller;
  final LevelSession session;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final total = session.totalQuestions;
    final n = (session.index + 1).clamp(1, total);
    return Row(
      children: [
        if (onExit != null) ...[
          IconButton(
            key: const ValueKey('exit'),
            tooltip: 'Thoát',
            iconSize: 36,
            onPressed: onExit,
            icon: const Icon(Icons.close),
          ),
          const SizedBox(width: 8),
        ],
        Text('Cấp ${controller.level.level}', style: t.bodyLarge),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text('$n/$total', style: t.bodyLarge),
                  if (session.isReview) ...[
                    const SizedBox(width: 12),
                    const Icon(Icons.replay, size: 28, color: AppTheme.yellow),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Ôn lại',
                        style: t.bodyLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ],
              ),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : (session.index / total).clamp(0, 1),
                  minHeight: 12,
                  color: AppTheme.accent,
                  backgroundColor: AppTheme.surface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        _TimerRing(controller: controller, session: session),
        const SizedBox(width: 20),
        Row(
          key: const ValueKey('score'),
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.star, color: AppTheme.yellow, size: 36),
            const SizedBox(width: 6),
            Text('${controller.score}', style: t.titleLarge),
          ],
        ),
      ],
    );
  }
}

/// The only part that follows the 60 Hz tick (see GameController.hudTick).
class _TimerRing extends StatelessWidget {
  const _TimerRing({required this.controller, required this.session});

  final GameController controller;
  final LevelSession session;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final limit = Scoring.timeFor(controller.level, ModeKind.laneJump);
    return ListenableBuilder(
      listenable: controller.hudTick,
      builder: (context, _) {
        final remaining = session.round.remaining;
        final frac = limit.inMilliseconds == 0
            ? 0.0
            : (remaining.inMilliseconds / limit.inMilliseconds).clamp(0.0, 1.0);
        final seconds = (remaining.inMilliseconds / 1000).ceil();
        return Semantics(
          label: 'Còn $seconds giây',
          excludeSemantics: true,
          child: SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: frac,
                    strokeWidth: 8,
                    color: frac < 0.25 ? AppTheme.orange : AppTheme.accent,
                    backgroundColor: AppTheme.surface,
                  ),
                ),
                Text('$seconds', style: t.bodyLarge),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _PromptArea extends StatelessWidget {
  const _PromptArea({required this.body});

  final _Body body;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final q = body.question;
    final c = body.controller;
    final ok = body.session.lastResult == RoundResult.correct;
    return LayoutBuilder(
      builder: (context, box) => Row(
        children: [
          Expanded(
            child: Center(
              child: QuestionPrompt(
                question: q,
                itemFor: c.itemFor,
                feedback: body._feedback,
              ),
            ),
          ),
          if (body._feedback)
            Row(
              key: const ValueKey('feedback-label'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  ok ? Icons.check_circle : Icons.cancel,
                  size: 56,
                  color: ok ? AppTheme.green : AppTheme.pink,
                ),
                const SizedBox(width: 8),
                Text(ok ? 'Đúng' : 'Sai', style: t.titleLarge),
                const SizedBox(width: 16),
              ],
            ),
          TinTin(
            state: !body._feedback
                ? TinTinState.idle
                : (ok ? TinTinState.happy : TinTinState.sad),
            size: box.maxHeight.clamp(64.0, 140.0),
            pulse: body.session.index,
          ),
        ],
      ),
    );
  }
}

/// The question prompt. It never shows the answer before the child chose:
/// the listen forms are a speaker icon only; after answering
/// ([feedback] true) listen-and-pick-picture reveals the spoken word.
class QuestionPrompt extends StatelessWidget {
  const QuestionPrompt({
    super.key,
    required this.question,
    required this.itemFor,
    this.feedback = false,
  });

  final ChoiceQuestion question;
  final ContentItem Function(String id) itemFor;
  final bool feedback;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final q = question;
    if (q.form == QuestionForm.seePicturePickWord) {
      final id = q.promptImageItemId;
      return id == null
          ? const SizedBox.shrink()
          : ItemPicture(
              key: const ValueKey('prompt-picture'),
              item: itemFor(id),
              size: 120,
            );
    }
    final reveal = feedback && q.form == QuestionForm.listenPickPicture;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.volume_up, size: 56, color: AppTheme.accent),
        const SizedBox(width: 16),
        Flexible(
          child: Text(
            reveal ? itemFor(q.itemId).word : 'Nghe nhé',
            style: t.titleLarge,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _Lanes extends StatelessWidget {
  const _Lanes({required this.body});

  final _Body body;

  @override
  Widget build(BuildContext context) {
    final q = body.question;
    final c = body.controller;
    final selected = c.selectedLane;
    final showAnswer =
        body._feedback && body.session.lastResult != RoundResult.correct;
    return Row(
      children: [
        for (var i = 0; i < q.choices.length; i++) ...[
          if (i > 0) const SizedBox(width: 16),
          Expanded(
            child: LaneTile(
              key: ValueKey('lane-$i'),
              option: q.choices[i],
              item: c.itemFor(q.choices[i].itemId),
              selected: i == selected,
              isAnswer: showAnswer && i == q.correctIndex,
            ),
          ),
        ],
      ],
    );
  }
}

/// One lane: picture and/or word, highlighted when the player stands in it
/// ("Em ở đây" marker), and a check mark on the right answer after a miss.
class LaneTile extends StatelessWidget {
  const LaneTile({
    super.key,
    required this.option,
    required this.item,
    required this.selected,
    this.isAnswer = false,
  });

  final ChoiceOption option;
  final ContentItem item;
  final bool selected;
  final bool isAnswer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      selected: selected,
      label: option.showWord ? item.word : 'Hình ${item.word}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? const Color(0xFF3A36A0) : AppTheme.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: selected ? AppTheme.accent : Colors.transparent,
            width: 6,
          ),
        ),
        padding: const EdgeInsets.all(12),
        child: Stack(
          children: [
            if (isAnswer)
              const Positioned(
                top: 0,
                right: 0,
                child: Icon(
                  Icons.check_circle,
                  size: 40,
                  color: AppTheme.green,
                ),
              ),
            Positioned.fill(child: _content(t)),
          ],
        ),
      ),
    );
  }

  Widget _content(TextTheme t) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Expanded(
          child: Center(
            // No scaling: words stay at full size; the picture takes
            // what is left (at least 32 px).
            child: LayoutBuilder(
              builder: (context, box) {
                final wordH = option.showWord ? 44.0 : 0.0;
                final gap = option.showPicture && option.showWord ? 8.0 : 0.0;
                final pic = (box.maxHeight - wordH - gap).clamp(32.0, 120.0);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (option.showPicture) ItemPicture(item: item, size: pic),
                    if (gap > 0) SizedBox(height: gap),
                    if (option.showWord)
                      Text(
                        item.word,
                        style: t.titleLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                  ],
                );
              },
            ),
          ),
        ),
        if (selected)
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.arrow_upward, size: 32, color: AppTheme.accent),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  'Em ở đây',
                  style: t.bodyLarge,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          )
        else
          const SizedBox(height: 40),
      ],
    );
  }
}

/// The item's bundled picture (`assets/images/<item.image>`). With no image,
/// or when the asset cannot be loaded, a coloured circle with the first
/// letter of the word is drawn instead. The word is the semantic label (for
/// screen readers only; never visible text).
class ItemPicture extends StatelessWidget {
  const ItemPicture({super.key, required this.item, this.size = 120});

  final ContentItem item;
  final double size;

  static const _palette = [
    AppTheme.accent,
    AppTheme.yellow,
    AppTheme.green,
    AppTheme.pink,
    AppTheme.orange,
    AppTheme.purple,
  ];

  static Color colorFor(String id) {
    var h = 0;
    for (final u in id.codeUnits) {
      h = (h * 31 + u) & 0x7fffffff;
    }
    return _palette[h % _palette.length];
  }

  /// Asset path of the item's picture, null when it has none.
  static String? assetFor(ContentItem item) {
    final img = item.image;
    return (img == null || img.isEmpty) ? null : 'assets/images/$img';
  }

  @override
  Widget build(BuildContext context) {
    final asset = assetFor(item);
    final fallback = _letterCircle(context);
    if (asset == null) return fallback;
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        asset,
        width: size,
        height: size,
        fit: BoxFit.contain,
        semanticLabel: item.word,
        errorBuilder: (context, error, stack) => fallback,
      ),
    );
  }

  Widget _letterCircle(BuildContext context) {
    final letter = item.word.isEmpty ? '?' : item.word[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colorFor(item.id),
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: Theme.of(context).textTheme.displayMedium!
            .copyWith(color: AppTheme.background),
      ),
    );
  }
}
