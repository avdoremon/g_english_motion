import 'package:flutter/material.dart';

import '../../app/game_controller.dart';
import '../../content/models.dart';
import '../../content/question_models.dart';
import '../../modes/round.dart';
import '../../session/level_session.dart';
import '../mascot/tin_tin.dart';
import '../theme/app_theme.dart';
import 'play_header.dart';
import 'round_verdict.dart';

/// The LaneJump play screen (Space Cadets, canvas B "Lane"): header (level,
/// progress, timer ring, score), the prompt, one lane per choice and Tin Tin
/// with the Đúng/Sai verdict.
///
/// Pictures: the bundled PNG (`assets/images/<item.image>`) is drawn by
/// [ItemPicture]; when the item has no image or the asset cannot be loaded it
/// falls back to a coloured circle with the first letter of the word.
///
/// Hints ("Gợi ý hình", `LevelConfig.hints`): on listen-and-pick-word lanes
/// the picture of each option is shown next to its word when
/// [GameController.showTileHints] says so (always for `full`, after half of
/// the time limit for `partial`, never for `none`). The pictures belong to
/// ALL options and nothing marks the right one before the child chose.
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

  /// Screens shorter than this (small landscape phones, 800x360) use tighter
  /// paddings and give the lanes more of the height, so the hint picture in a
  /// word tile stays recognisable while words keep their full size.
  static const compactBelow = 420.0;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxHeight < compactBelow;
          final gap = compact ? 6.0 : 12.0;
          return Padding(
            padding: compact
                ? const EdgeInsets.fromLTRB(24, 6, 24, 8)
                : const EdgeInsets.fromLTRB(24, 12, 24, 16),
            child: Column(
              children: [
                PlayHeader(
                  controller: controller,
                  session: session,
                  onExit: onExit,
                ),
                SizedBox(height: gap),
                Expanded(
                  flex: compact ? 2 : 3,
                  child: _PromptArea(body: this),
                ),
                SizedBox(height: gap),
                Expanded(flex: 5, child: _Lanes(body: this)),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PromptArea extends StatelessWidget {
  const _PromptArea({required this.body});

  final _Body body;

  @override
  Widget build(BuildContext context) {
    final q = body.question;
    final c = body.controller;
    final result = body.session.lastResult;
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
          if (body._feedback) RoundVerdict(result: result, iconSize: 56),
          TinTin(
            state: RoundVerdict.mascotFor(result, feedback: body._feedback),
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
    final q = question;
    if (q.form == QuestionForm.seePicturePickWord) {
      final id = q.promptImageItemId;
      return id == null
          ? const SizedBox.shrink()
          : ItemPicture(
              key: const ValueKey('prompt-picture'),
              item: itemFor(id),
              size: 120,
              // Never the word: a screen reader would announce the answer.
              semanticLabel: 'Hình cần chọn',
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
            style: AppTheme.textStyles.play,
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
    final hint = c.showTileHints;
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
              showHintPicture: hint,
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
    this.showHintPicture = false,
  });

  final ChoiceOption option;
  final ContentItem item;
  final bool selected;
  final bool isAnswer;

  /// Hint: draw the item's picture above its word. The same flag is passed
  /// to every lane, so it never singles out the right one. Items without a
  /// bundled picture show only their word.
  final bool showHintPicture;

  bool get _showPicture =>
      option.showPicture ||
      (showHintPicture &&
          option.showWord &&
          ItemPicture.assetFor(item) != null);

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return LayoutBuilder(
      builder: (context, box) {
        // Short tile: less padding, so the picture gets the room.
        final pad = box.maxHeight < 200 ? 6.0 : 12.0;
        return _frame(t, pad);
      },
    );
  }

  Widget _frame(TextTheme t, double pad) {
    return Semantics(
      selected: selected,
      label: option.showWord ? item.word : 'Hình ${item.word}',
      excludeSemantics: true,
      child: Container(
        decoration: BoxDecoration(
          color: selected ? AppTheme.selectedFill : AppTheme.surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: selected ? AppTheme.accent : Colors.transparent,
            width: 6,
          ),
        ),
        padding: EdgeInsets.all(pad),
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
                // The word line is ~48.5 px tall at 28 sp; with a picture too
                // the picture takes what is left (at least 24 px on the
                // smallest phones, 32 px when it is the only content).
                final both = _showPicture && option.showWord;
                final wordH = option.showWord ? 50.0 : 0.0;
                final gap = both ? 8.0 : 0.0;
                final pic = (box.maxHeight - wordH - gap).clamp(
                  both ? 24.0 : 32.0,
                  120.0,
                );
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_showPicture)
                      ItemPicture(
                        item: item,
                        size: pic,
                        semanticLabel: item.word,
                      ),
                    if (gap > 0) SizedBox(height: gap),
                    if (option.showWord)
                      Text(
                        item.word,
                        style: AppTheme.textStyles.play,
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
/// letter of the word is drawn instead. [semanticLabel] is for screen readers
/// only (never visible text); lane tiles pass the word, the prompt picture a
/// neutral label.
class ItemPicture extends StatelessWidget {
  const ItemPicture({
    super.key,
    required this.item,
    this.size = 120,
    this.semanticLabel,
  });

  final ContentItem item;
  final double size;

  /// Announced by screen readers. Null (the default) means the picture is
  /// silent: a prompt picture must never name the word it asks for.
  final String? semanticLabel;

  static const _palette = [
    AppTheme.accent,
    AppTheme.yellow,
    AppTheme.green,
    AppTheme.coral,
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
    // One node for the whole picture (image or letter circle): exactly the
    // given label, or silence. The letter of the fallback is never read out.
    return Semantics(
      label: semanticLabel,
      image: true,
      excludeSemantics: true,
      child: asset == null
          ? fallback
          : SizedBox(
              width: size,
              height: size,
              child: Image.asset(
                asset,
                width: size,
                height: size,
                fit: BoxFit.contain,
                semanticLabel: semanticLabel,
                errorBuilder: (context, error, stack) => fallback,
              ),
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
        style: AppTheme.textStyles.title.copyWith(color: AppTheme.background),
      ),
    );
  }
}
