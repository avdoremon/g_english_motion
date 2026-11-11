import 'package:flutter/material.dart';

import '../../modes/round.dart';
import '../mascot/tin_tin.dart';
import '../theme/app_theme.dart';

/// The verdict of a finished round, shown the same way by all three play
/// screens (LaneJump, DragSpell, SkyShoot).
///
/// A [RoundResult.timeout] is NEVER shown as a mistake: the most likely cause
/// is an answer the pose layer never saw (a jump that was not recognised),
/// and this game does not blame the child for its own input. It gets the
/// neutral "Hết giờ" with an hourglass and an idle mascot; only a real
/// [RoundResult.wrong] says "Sai".
class RoundVerdict extends StatelessWidget {
  const RoundVerdict({
    super.key,
    required this.result,
    this.iconSize = 48,
    this.trailing = 16,
    this.correctLabel,
    this.wrongLabel,
  });

  /// The round's result ([LevelSession.lastResult]).
  final RoundResult? result;
  final double iconSize;

  /// Optional wording overrides for screens whose answer buttons already say
  /// "Đúng"/"Sai" (yesNo). Null keeps the shared wording; a timeout is
  /// always "Hết giờ".
  final String? correctLabel, wrongLabel;

  /// Space kept after the label (the mascot follows it in every screen).
  final double trailing;

  static bool isCorrect(RoundResult? r) => r == RoundResult.correct;
  static bool isTimeout(RoundResult? r) => r == RoundResult.timeout;

  static String labelFor(RoundResult? r) => switch (r) {
    RoundResult.correct => 'Đúng',
    RoundResult.timeout => 'Hết giờ',
    _ => 'Sai',
  };

  static IconData iconFor(RoundResult? r) => switch (r) {
    RoundResult.correct => Icons.check_circle,
    RoundResult.timeout => Icons.hourglass_bottom,
    _ => Icons.cancel,
  };

  static Color colorFor(RoundResult? r) => switch (r) {
    RoundResult.correct => AppTheme.green,
    RoundResult.timeout => AppTheme.muted,
    _ => AppTheme.coral,
  };

  /// Tin Tin's state for a round result: cheerful when right, neutral on a
  /// timeout, sad only on a real mistake. Outside feedback the mascot idles.
  static TinTinState mascotFor(RoundResult? r, {bool feedback = true}) {
    if (!feedback) return TinTinState.idle;
    return switch (r) {
      RoundResult.correct => TinTinState.happy,
      RoundResult.timeout => TinTinState.idle,
      _ => TinTinState.sad,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const ValueKey('feedback-label'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(iconFor(result), size: iconSize, color: colorFor(result)),
        const SizedBox(width: 8),
        Text(switch (result) {
          RoundResult.correct => correctLabel ?? labelFor(result),
          RoundResult.timeout => labelFor(result),
          _ => wrongLabel ?? labelFor(result),
        }, style: AppTheme.textStyles.heading),
        SizedBox(width: trailing),
      ],
    );
  }
}
