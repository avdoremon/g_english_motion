import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Row of [total] stars, the first [earned] filled yellow.
class StarRow extends StatelessWidget {
  const StarRow({
    super.key,
    required this.earned,
    this.total = 3,
    this.size = 40,
  });

  final int earned;
  final int total;
  final double size;

  @override
  Widget build(BuildContext context) {
    final gap = size / 8 < 2 ? 2.0 : size / 8;
    return Semantics(
      label: '$earned trên $total sao',
      excludeSemantics: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < total; i++) ...[
            if (i > 0) SizedBox(width: gap),
            CustomPaint(
              key: Key(i < earned ? 'star-on-$i' : 'star-off-$i'),
              size: Size.square(size),
              painter: StarPainter(on: i < earned),
            ),
          ],
        ],
      ),
    );
  }
}

/// Five-point star from the canvas polygon, ink ring.
class StarPainter extends CustomPainter {
  const StarPainter({required this.on});
  final bool on;

  static const _pts = <Offset>[
    Offset(0, -10),
    Offset(3, -3),
    Offset(10, -3),
    Offset(4.5, 2),
    Offset(6.5, 9.5),
    Offset(0, 5),
    Offset(-6.5, 9.5),
    Offset(-4.5, 2),
    Offset(-10, -3),
    Offset(-3, -3),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    final path = Path();
    for (var i = 0; i < _pts.length; i++) {
      final p = Offset(12 * k + _pts[i].dx * k, 12 * k + _pts[i].dy * k);
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    path.close();
    canvas.drawPath(
      path,
      Paint()..color = on ? AppTheme.yellow : AppTheme.trackWhite,
    );
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6 * k
        ..strokeJoin = StrokeJoin.round
        ..color = AppTheme.ink,
    );
  }

  @override
  bool shouldRepaint(StarPainter old) => old.on != on;
}
