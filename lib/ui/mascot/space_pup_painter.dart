import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'tin_tin.dart';

/// Space Puppy (canvas board "CharPuppy"), drawn on a 200x240 design grid and
/// scaled to fit the square paint area.
class SpacePupPainter extends CustomPainter {
  SpacePupPainter({required this.state, required this.t});

  final TinTinState state;

  /// Animation phase, 0..1 within one cycle.
  final double t;

  static const _ink = Color(0xFF0E1033);
  static const _purple = Color(0xFF6C4DFF);
  static const _cyanGlass = Color(0x33BEEBFF);
  static const _yellow = Color(0xFFFFD23F);
  static const _coral = Color(0xFFFF6B6B);
  static const _cream = Color(0xFFFFE3BC);
  static const _brown = Color(0xFFB9783F);
  static const _white = Color(0xFFFFFFFF);

  bool get _joy =>
      state == TinTinState.cheer ||
      state == TinTinState.dance ||
      state == TinTinState.happy;

  Paint _fill(Color c) => Paint()..color = c;
  Paint _line(Color c, double w) => Paint()
    ..color = c
    ..style = PaintingStyle.stroke
    ..strokeWidth = w
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void _outlined(Canvas c, Path p, Color fill, double sw) {
    c.drawPath(p, _fill(fill));
    c.drawPath(p, _line(_ink, sw));
  }

  void _limb(Canvas c, Path p, Color col, double w, double ow) {
    c.drawPath(p, _line(_ink, ow));
    c.drawPath(p, _line(col, w));
  }

  void _star(Canvas c, double cx, double cy, double s) {
    const pts = [
      [0, -10],
      [3, -3],
      [10, -3],
      [4.5, 2],
      [6.5, 9.5],
      [0, 5],
      [-6.5, 9.5],
      [-4.5, 2],
      [-10, -3],
      [-3, -3],
    ];
    final p = Path();
    for (var i = 0; i < pts.length; i++) {
      final x = cx + pts[i][0] * s, y = cy + pts[i][1] * s;
      i == 0 ? p.moveTo(x, y) : p.lineTo(x, y);
    }
    p.close();
    _outlined(c, p, _yellow, 2.5);
  }

  Path _arm(double x0, double y0, double cx, double cy, double x1, double y1) =>
      Path()
        ..moveTo(x0, y0)
        ..quadraticBezierTo(cx, cy, x1, y1);

  RRect _rr(double x, double y, double w, double h, double r) =>
      RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), Radius.circular(r));

  @override
  void paint(Canvas canvas, Size size) {
    final k = math.min(size.width, size.height) / 240;
    final phase = math.sin(t * 2 * math.pi);
    final animated = state == TinTinState.cheer || state == TinTinState.dance;

    canvas.save();
    canvas.translate((size.width - 200 * k) / 2, (size.height - 240 * k) / 2);
    canvas.scale(k);
    canvas.translate(0, 14);
    if (state == TinTinState.dance) {
      canvas.translate(100, 140);
      canvas.rotate(phase * 0.1);
      canvas.translate(-100, -140);
    }
    if (animated) canvas.translate(0, -phase.abs() * 8);

    // Tail (wags with phase when animated).
    final wag = animated ? phase * 10 : 0.0;
    _limb(
      canvas,
      _arm(132, 192, 166 + wag, 188, 162 + wag, 156),
      _cream,
      7,
      16,
    );

    // Feet.
    for (final x in [74.0, 104.0]) {
      final r = _rr(x, 196, 22, 24, 10);
      canvas.drawRRect(r, _fill(_coral));
      canvas.drawRRect(r, _line(_ink, 5));
    }

    // Suit body + star badge.
    final body = _rr(68, 142, 64, 62, 26);
    canvas.drawRRect(body, _fill(_purple));
    canvas.drawRRect(body, _line(_ink, 6));
    _star(canvas, 100, 176, 1.2);

    // Arms: idle / cheer (raised) / sad (drooped).
    final raised = state == TinTinState.cheer || state == TinTinState.dance;
    final lift = animated ? phase * 8 : 0.0; // alternating wave
    late final Path l, r;
    late final Offset lh, rh;
    if (raised) {
      l = _arm(72, 158, 38, 150, 44, 110 - lift);
      r = _arm(128, 158, 162, 150, 156, 110 + lift);
      lh = Offset(44, 104 - lift);
      rh = Offset(156, 104 + lift);
    } else if (state == TinTinState.sad) {
      l = _arm(72, 164, 60, 184, 66, 204);
      r = _arm(128, 164, 140, 184, 134, 204);
      lh = const Offset(66, 206);
      rh = const Offset(134, 206);
    } else {
      l = _arm(72, 160, 54, 176, 58, 198);
      r = _arm(128, 160, 146, 176, 142, 198);
      lh = const Offset(58, 200);
      rh = const Offset(142, 200);
    }
    _limb(canvas, l, _purple, 8, 18);
    _limb(canvas, r, _purple, 8, 18);
    for (final h in [lh, rh]) {
      canvas.drawCircle(h, 10, _fill(_cream));
      canvas.drawCircle(h, 10, _line(_ink, 5));
    }

    // Collar.
    final collar = Rect.fromCenter(
      center: const Offset(100, 146),
      width: 80,
      height: 20,
    );
    canvas.drawOval(collar, _fill(_yellow));
    canvas.drawOval(collar, _line(_ink, 5));

    // Ears.
    final flap = animated ? phase * 6 : 0.0;
    final Path le, re;
    if (state == TinTinState.sad) {
      le = Path()
        ..moveTo(58, 72)
        ..quadraticBezierTo(22, 86, 30, 132)
        ..quadraticBezierTo(50, 130, 62, 100)
        ..close();
      re = Path()
        ..moveTo(142, 72)
        ..quadraticBezierTo(178, 86, 170, 132)
        ..quadraticBezierTo(150, 130, 138, 100)
        ..close();
    } else {
      le = Path()
        ..moveTo(58, 66)
        ..quadraticBezierTo(26 - flap, 64, 28 - flap, 112)
        ..quadraticBezierTo(46, 118, 62, 94)
        ..close();
      re = Path()
        ..moveTo(142, 66)
        ..quadraticBezierTo(174 + flap, 64, 172 + flap, 112)
        ..quadraticBezierTo(154, 118, 138, 94)
        ..close();
    }
    _outlined(canvas, le, _brown, 5);
    _outlined(canvas, re, _brown, 5);

    // Head, eye patch, muzzle, nose, cheeks.
    final head = Rect.fromCenter(
      center: const Offset(100, 96),
      width: 92,
      height: 84,
    );
    canvas.drawOval(head, _fill(_cream));
    canvas.drawOval(head, _line(_ink, 5));
    canvas.drawCircle(const Offset(80, 86), 14, _fill(_brown));
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 112), width: 48, height: 34),
      _fill(_white),
    );
    canvas.drawOval(
      Rect.fromCenter(center: const Offset(100, 103), width: 18, height: 13),
      _fill(_ink),
    );
    final cheek = _fill(_coral.withValues(alpha: 0.5));
    canvas.drawCircle(const Offset(66, 106), 6, cheek);
    canvas.drawCircle(const Offset(134, 106), 6, cheek);

    // Face.
    if (_joy) {
      canvas.drawPath(
        Path()
          ..moveTo(72, 90)
          ..quadraticBezierTo(80, 77, 88, 90)
          ..moveTo(112, 90)
          ..quadraticBezierTo(120, 77, 128, 90),
        _line(_ink, 5),
      );
      if (state == TinTinState.happy) {
        _smile(canvas);
      } else {
        final mouth = Path()
          ..moveTo(86, 116)
          ..quadraticBezierTo(100, 142, 114, 116)
          ..close();
        canvas.drawPath(mouth, _fill(_ink));
        canvas.drawPath(mouth, _line(_ink, 3));
        canvas.drawOval(
          Rect.fromCenter(
            center: const Offset(100, 128),
            width: 16,
            height: 10,
          ),
          _fill(_coral),
        );
      }
    } else {
      canvas.drawCircle(const Offset(80, 86), 7, _fill(_ink));
      canvas.drawCircle(const Offset(120, 86), 7, _fill(_ink));
      canvas.drawCircle(const Offset(82, 84), 2.6, _fill(_white));
      canvas.drawCircle(const Offset(122, 84), 2.6, _fill(_white));
      if (state == TinTinState.sad) {
        // Soft worried brows and a small frown; no tears.
        canvas.drawPath(
          Path()
            ..moveTo(70, 78)
            ..lineTo(90, 70)
            ..moveTo(130, 78)
            ..lineTo(110, 70),
          _line(_ink, 4.5),
        );
        canvas.drawPath(
          Path()
            ..moveTo(88, 126)
            ..quadraticBezierTo(100, 115, 112, 126),
          _line(_ink, 4),
        );
      } else {
        _smile(canvas);
      }
    }

    // Helmet glass + glint + antenna.
    canvas.drawCircle(const Offset(100, 92), 68, _fill(_cyanGlass));
    canvas.drawCircle(const Offset(100, 92), 68, _line(_ink, 6));
    canvas.drawPath(
      Path()
        ..moveTo(50, 72)
        ..quadraticBezierTo(58, 50, 82, 40),
      _line(_white.withValues(alpha: 0.85), 6),
    );
    canvas.drawLine(
      const Offset(100, 24),
      const Offset(100, 10),
      _line(_ink, 6),
    );
    _star(canvas, 100, 6, 1.3);

    canvas.restore();
  }

  void _smile(Canvas canvas) {
    canvas.drawPath(
      Path()
        ..moveTo(100, 109)
        ..lineTo(100, 116)
        ..moveTo(100, 116)
        ..quadraticBezierTo(91, 126, 84, 119)
        ..moveTo(100, 116)
        ..quadraticBezierTo(109, 126, 116, 119),
      _line(_ink, 3.5),
    );
  }

  @override
  bool shouldRepaint(SpacePupPainter old) => old.state != state || old.t != t;
}
