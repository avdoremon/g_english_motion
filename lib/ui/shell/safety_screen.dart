import 'package:flutter/material.dart';

import '../../progress/progress_store.dart';
import '../mascot/tin_tin.dart';
import '../theme/app_theme.dart';

class SafetyScreen extends StatelessWidget {
  const SafetyScreen({
    super.key,
    required this.store,
    required this.onAcknowledged,
  });

  final ProgressStore store;
  final VoidCallback onAcknowledged;

  static bool needed(ProgressStore s) => !s.safetyAcknowledged;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TinTin(state: TinTinState.idle, size: 120),
            const SizedBox(height: 16),
            Text('Trước khi chơi nhé', style: AppTheme.textStyles.heading),
            const SizedBox(height: 16),
            Text(
              'Nhờ bố mẹ dọn khoảng trống trước TV, '
              'và cố định điện thoại thật chắc.',
              style: t.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () async {
                final done = store.acknowledgeSafety();
                onAcknowledged();
                await done;
              },
              child: const Text('Đã hiểu'),
            ),
          ],
        ),
      ),
    );
  }
}
