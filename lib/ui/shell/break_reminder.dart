import 'package:flutter/material.dart';

import '../mascot/tin_tin.dart';
import '../theme/app_theme.dart';

/// "Take a break" after every 20 minutes of play.
///
/// Visible, not just spoken: a 3 s caption is gone before a child busy
/// jumping has read it, and the reminder is really meant for the grown-up in
/// the room. The game is paused while this is up and only a deliberate tap
/// ("Chơi tiếp") dismisses it - in the style of [PauseOverlay], but with a
/// button, because nothing else ends it.
class BreakReminder extends StatelessWidget {
  const BreakReminder({super.key, required this.onDismiss});

  static const message = 'Nghỉ một chút nhé!';
  static const hint =
      'Em đứng lên vươn vai và uống nước nha. '
      'Bố mẹ bấm "Chơi tiếp" khi em nghỉ xong.';

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: ColoredBox(
        color: AppTheme.breakScrim,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const TinTin(state: TinTinState.idle, size: 96),
                const SizedBox(height: 8),
                Text(message, style: t.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: 8),
                Text(
                  hint,
                  style: t.bodyLarge!.copyWith(color: AppTheme.muted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  key: const ValueKey('break-dismiss'),
                  onPressed: onDismiss,
                  child: const Text('Chơi tiếp'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
