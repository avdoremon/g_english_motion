import 'package:flutter/material.dart';

import '../../app/game_controller.dart';
import '../../session/level_session.dart';
import '../theme/app_theme.dart';

/// Header shared by the play screens: level, question progress, review
/// marker, timer ring and score.
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
        TimerRing(controller: controller, session: session),
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
class TimerRing extends StatelessWidget {
  const TimerRing({super.key, required this.controller, required this.session});

  final GameController controller;
  final LevelSession session;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final limit = session.round.timeLimit;
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
