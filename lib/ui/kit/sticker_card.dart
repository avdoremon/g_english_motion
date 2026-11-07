import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// White "sticker": 5 px ink border, radius 24, hard shadow, optional tilt
/// (degrees, keep within +-3).
class StickerCard extends StatelessWidget {
  const StickerCard({super.key, required this.child, this.tilt = 0, this.fill});

  final Widget child;
  final double tilt;
  final Color? fill;

  @override
  Widget build(BuildContext context) {
    final card = DecoratedBox(
      decoration: BoxDecoration(
        color: fill ?? Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.ink, width: 5),
        boxShadow: const [
          BoxShadow(color: AppTheme.shadow, offset: Offset(0, 8)),
        ],
      ),
      child: Padding(padding: const EdgeInsets.all(12), child: child),
    );
    return Transform.rotate(angle: tilt * math.pi / 180, child: card);
  }
}
