import 'package:flutter/material.dart';

import '../../session/level_session.dart';
import '../mascot/tin_tin.dart';
import '../theme/app_theme.dart';

/// End-of-level screen: 0-3 stars (filled star vs outlined star, so it is
/// not colour-only), correct/total, points and the two buttons. When the
/// level did not unlock the next one, the second button reads "Về trang
/// chính" (the app maps [onNext] to going home in that case).
class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    required this.outcome,
    required this.onPlayAgain,
    required this.onNext,
  });

  final LevelOutcome outcome;
  final VoidCallback onPlayAgain;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final stars = outcome.stars.clamp(0, 3);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TinTin(
              state: stars >= 1 ? TinTinState.cheer : TinTinState.sad,
              size: 160,
            ),
            const SizedBox(height: 8),
            Text(stars >= 1 ? 'Giỏi lắm!' : 'Cố lên nào!', style: t.titleLarge),
            const SizedBox(height: 8),
            Semantics(
              label: '$stars trên 3 sao',
              excludeSemantics: true,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < 3; i++)
                    Icon(
                      i < stars ? Icons.star : Icons.star_border,
                      size: 64,
                      color: i < stars ? AppTheme.yellow : AppTheme.muted,
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Đúng ${outcome.correct}/${outcome.total}',
              style: t.bodyLarge,
            ),
            Text('${outcome.points} điểm', style: t.bodyLarge),
            const SizedBox(height: 24),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 16,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: onPlayAgain,
                  icon: const Icon(Icons.replay),
                  label: const Text('Chơi lại'),
                ),
                FilledButton.icon(
                  onPressed: onNext,
                  icon: Icon(
                    outcome.unlockedNext ? Icons.arrow_forward : Icons.home,
                  ),
                  label: Text(
                    outcome.unlockedNext ? 'Tiếp tục' : 'Về trang chính',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
