import 'package:flutter/material.dart';

import '../../input/pose_frame_source.dart';
import '../mascot/tin_tin.dart';

class PermissionScreen extends StatelessWidget {
  const PermissionScreen({
    super.key,
    required this.outcome,
    required this.onRetry,
    required this.onOpenSettings,
  });

  final PermissionOutcome outcome;
  final VoidCallback onRetry;
  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final permanent = outcome == PermissionOutcome.permanentlyDenied;
    if (outcome == PermissionOutcome.unavailable) {
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const TinTin(state: TinTinState.sad, size: 120),
              const SizedBox(height: 16),
              Text(
                'Camera chưa sẵn sàng trên máy này',
                style: t.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
            ],
          ),
        ),
      );
    }
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TinTin(state: TinTinState.sad, size: 120),
            const SizedBox(height: 16),
            Text(
              'Tin Tin cần camera để nhìn thấy em chơi. '
              'Hình ảnh chỉ xử lý trên máy, không gửi đi đâu cả.',
              style: t.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            if (permanent) ...[
              Text(
                'Nhờ bố mẹ bật quyền camera trong Cài đặt nhé.',
                style: t.bodyLarge,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onOpenSettings,
                child: const Text('Mở Cài đặt'),
              ),
            ] else
              FilledButton(onPressed: onRetry, child: const Text('Thử lại')),
          ],
        ),
      ),
    );
  }
}
