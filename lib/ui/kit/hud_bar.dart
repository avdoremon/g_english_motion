import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'star_row.dart';

/// Compact top bar: star count pill, time ring, optional trailing widget.
class HudBar extends StatelessWidget {
  const HudBar({
    super.key,
    required this.stars,
    required this.timeFraction,
    required this.trailing,
  });

  final int stars;

  /// Remaining time, 0..1.
  final double timeFraction;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final frac = timeFraction.clamp(0.0, 1.0);
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: const Color(0x40000000),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 16, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CustomPaint(
                    size: const Size.square(30),
                    painter: const StarPainter(on: true),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '$stars',
                    style: AppTheme.textStyles.play.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Spacer(),
          Semantics(
            label: 'Thời gian còn lại',
            excludeSemantics: true,
            child: SizedBox(
              width: 56,
              height: 56,
              child: CustomPaint(painter: _TimeRing(frac)),
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 16), trailing!],
        ],
      ),
    );
  }
}

class _TimeRing extends CustomPainter {
  _TimeRing(this.frac);
  final double frac;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width * 23 / 56;
    canvas.drawCircle(c, r, Paint()..color = const Color(0x38000000));
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(c, r, track..color = const Color(0x29FFFFFF));
    canvas.drawArc(
      Rect.fromCircle(center: c, radius: r),
      -1.5707963,
      6.2831853 * frac,
      false,
      track..color = frac > 0.25 ? AppTheme.accent : AppTheme.coral,
    );
  }

  @override
  bool shouldRepaint(_TimeRing old) => old.frac != frac;
}
