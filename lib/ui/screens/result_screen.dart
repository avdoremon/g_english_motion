import 'package:flutter/material.dart';

import '../../session/level_session.dart';
import '../kit/kit.dart';
import '../mascot/tin_tin.dart';
import '../theme/app_theme.dart';

/// End-of-level screen: 0-3 stars (a [StarRow]: filled vs dim, so it is
/// not colour-only), correct/total, points and the two buttons. When the
/// level did not unlock the next one, the second button reads "Về trang
/// chính" (the app maps [onNext] to going home in that case).
class ResultScreen extends StatelessWidget {
  const ResultScreen({
    super.key,
    required this.outcome,
    required this.onPlayAgain,
    required this.onNext,
    this.hasNext = true,
  });

  final LevelOutcome outcome;
  final VoidCallback onPlayAgain;
  final VoidCallback onNext;

  /// False on the last level: there is nothing to continue to, so the
  /// second button always goes home.
  final bool hasNext;

  bool get _forward => outcome.unlockedNext && hasNext;

  @override
  Widget build(BuildContext context) {
    final stars = outcome.stars.clamp(0, 3);
    final play = AppTheme.textStyles.play;
    Widget chip(String text) => DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0x4D000000),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(text, maxLines: 1, style: play),
        ),
      ),
    );
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, box) {
          final compact = box.maxHeight < 500;
          final puppy = (box.maxHeight * (compact ? 0.42 : 0.55)).clamp(
            120.0,
            250.0,
          );
          final starSize = compact ? 64.0 : 96.0;
          final content = Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  stars >= 1 ? 'Giỏi lắm!' : 'Cố lên nào!',
                  maxLines: 1,
                  style: compact
                      ? AppTheme.textStyles.title
                      : AppTheme.textStyles.display,
                ),
              ),
              SizedBox(height: compact ? 6 : 12),
              StarRow(earned: stars, size: starSize),
              SizedBox(height: compact ? 6 : 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 14,
                runSpacing: 8,
                children: [
                  chip('Đúng ${outcome.correct}/${outcome.total}'),
                  chip('${outcome.points} điểm'),
                ],
              ),
              SizedBox(height: compact ? 12 : 20),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 18,
                runSpacing: 14,
                children: [
                  BigButton(
                    label: 'Chơi lại',
                    icon: Icons.replay,
                    color: AppTheme.accent,
                    onPressed: onPlayAgain,
                  ),
                  BigButton(
                    label: _forward ? 'Tiếp tục' : 'Về trang chính',
                    icon: _forward ? Icons.arrow_forward : Icons.home,
                    onPressed: onNext,
                  ),
                ],
              ),
            ],
          );
          return Center(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(compact ? 12 : 24),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TinTin(
                    state: switch (stars) {
                      0 => TinTinState.sad,
                      1 => TinTinState.happy,
                      _ => TinTinState.cheer,
                    },
                    size: puppy,
                  ),
                  SizedBox(width: compact ? 20 : 32),
                  Flexible(child: content),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
