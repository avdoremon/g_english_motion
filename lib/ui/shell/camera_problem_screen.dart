import 'package:flutter/material.dart';

import '../mascot/tin_tin.dart';

/// Shown when the camera delivers nothing usable (no frames, persistent
/// errors, calibration that never finishes). The child gets two big buttons;
/// the second paragraph is for the grown-up.
class CameraProblemScreen extends StatelessWidget {
  const CameraProblemScreen({
    super.key,
    required this.onRetry,
    required this.onHome,
  });

  final VoidCallback onRetry;
  final VoidCallback onHome;

  static const title = 'Camera không hoạt động';
  static const parentHint = 'Kiểm tra quyền camera và khởi động lại ứng dụng';

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TinTin(state: TinTinState.sad, size: 120),
            const SizedBox(height: 16),
            Text(title, style: t.titleLarge, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(parentHint, style: t.bodyLarge, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              alignment: WrapAlignment.center,
              children: [
                FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
                OutlinedButton(
                  onPressed: onHome,
                  child: const Text('Về trang chính'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
