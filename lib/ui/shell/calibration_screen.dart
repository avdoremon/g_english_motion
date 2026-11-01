import 'package:flutter/material.dart';

import '../../input/calibrator.dart';
import '../mascot/tin_tin.dart';
import '../theme/app_theme.dart';

class CalibrationScreen extends StatelessWidget {
  const CalibrationScreen({super.key, required this.progress});

  final CalibrationProgress progress;

  static String instructionFor(CalibrationIssue? issue) => switch (issue) {
    CalibrationIssue.tooClose => 'Lùi ra xa hơn một chút',
    CalibrationIssue.notStill => 'Đứng yên một chút nhé',
    CalibrationIssue.notCentered => 'Đứng vào giữa màn hình',
    CalibrationIssue.noPerson => 'Em chưa vào khung hình',
    null => 'Giữ yên nhé…',
  };

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                SizedBox.expand(
                  child: CircularProgressIndicator(
                    value: progress.progress.clamp(0.0, 1.0),
                    strokeWidth: 14,
                    color: AppTheme.accent,
                    backgroundColor: AppTheme.surface,
                  ),
                ),
                const TinTin(state: TinTinState.idle, size: 120),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Text(
            instructionFor(progress.issue),
            style: t.bodyLarge,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
