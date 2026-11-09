import 'dart:math' as math;

import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';

/// Paints the hand cursor: a soft disc, a track, the hold progress as a
/// rounded arc from the top (clockwise) and a white dot at the centre.
class HoldRingPainter extends CustomPainter {
  const HoldRingPainter({required this.progress});

  /// 0..1 progress of the current hold.
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final unit = size.shortestSide / 56;
    final r = 22 * unit;
    canvas.drawCircle(
      c,
      r,
      Paint()..color = AppTheme.accent.withValues(alpha: 0.3),
    );
    canvas.drawCircle(
      c,
      r,
      Paint()
        ..color = AppTheme.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4 * unit,
    );
    final p = progress.clamp(0.0, 1.0);
    if (p > 0) {
      canvas.drawArc(
        Rect.fromCircle(center: c, radius: r),
        -math.pi / 2,
        2 * math.pi * p,
        false,
        Paint()
          ..color = AppTheme.yellow
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeWidth = 6 * unit,
      );
    }
    canvas.drawCircle(c, 7 * unit, Paint()..color = AppTheme.text);
  }

  @override
  bool shouldRepaint(HoldRingPainter old) => old.progress != progress;
}
