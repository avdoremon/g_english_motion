import 'package:flutter/material.dart';

import '../../app/game_controller.dart';
import '../../session/level_session.dart';
import '../kit/kit.dart';
import '../theme/app_theme.dart';

/// Header shared by the play screens: exit, level chip, segmented question
/// progress, review marker, score pill and timer ring (a [HudBar]).
class PlayHeader extends StatelessWidget {
  const PlayHeader({
    super.key,
    required this.controller,
    required this.session,
    this.onExit,
  });

  final GameController controller;
  final LevelSession session;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    final total = session.totalQuestions;
    final n = (session.index + 1).clamp(1, total);
    final limit = session.round.timeLimit;
    return Row(
      children: [
        if (onExit != null) ...[
          // Keyed here so the key sits on the tappable 56 dp target.
          RoundIconButton(
            key: const ValueKey('exit'),
            icon: Icons.close,
            semanticLabel: 'Thoát',
            onPressed: onExit!,
          ),
          const SizedBox(width: 12),
        ],
        Expanded(
          // The header follows the 60 Hz tick only for the ring; the rest is
          // a handful of widgets, cheap to rebuild with it.
          child: ListenableBuilder(
            listenable: controller.hudTick,
            builder: (context, _) {
              final remaining = session.round.remaining;
              final frac = limit.inMilliseconds == 0
                  ? 0.0
                  : (remaining.inMilliseconds / limit.inMilliseconds).clamp(
                      0.0,
                      1.0,
                    );
              return HudBar(
                scoreKey: const ValueKey('score'),
                stars: controller.score,
                timeFraction: frac,
                seconds: (remaining.inMilliseconds / 1000).ceil(),
                trailing: null,
                middle: _Middle(
                  level: controller.level.level,
                  n: n,
                  total: total,
                  review: session.isReview,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Middle extends StatelessWidget {
  const _Middle({
    required this.level,
    required this.n,
    required this.total,
    required this.review,
  });

  final int level;
  final int n;
  final int total;
  final bool review;

  @override
  Widget build(BuildContext context) {
    final play = AppTheme.textStyles.play;
    return Row(
      children: [
        Flexible(
          flex: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppTheme.purple,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Cấp $level',
                  maxLines: 1,
                  style: play.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            key: const ValueKey('progress'),
            children: [
              for (var k = 0; k < total; k++) ...[
                if (k > 0) const SizedBox(width: 4),
                Expanded(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: k < n - 1
                          ? AppTheme.accent
                          : (k == n - 1
                                ? AppTheme.yellow
                                : const Color(0x29FFFFFF)),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const SizedBox(height: 14),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          flex: 0,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text('$n/$total', maxLines: 1, style: play),
          ),
        ),
        if (review) ...[
          const SizedBox(width: 12),
          const Icon(Icons.replay, size: 28, color: AppTheme.yellow),
          const SizedBox(width: 4),
          Flexible(
            flex: 0,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('Ôn lại', maxLines: 1, style: play),
            ),
          ),
        ],
      ],
    );
  }
}
