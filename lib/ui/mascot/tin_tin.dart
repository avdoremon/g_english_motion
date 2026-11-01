import 'dart:math' as math;

import 'package:flutter/material.dart';

enum TinTinState { idle, happy, sad, cheer, dance }

/// Tin Tin, the round teal mascot with long ears, drawn with [CustomPaint].
///
/// cheer/dance play a short bounded animation: [cycles] cycles of [cycle]
/// (1.2 s, below the 1.5 s cap, ~0.8 Hz so nothing flashes above 3 Hz) and
/// then rest. Other states are static.
class TinTin extends StatelessWidget {
  const TinTin({super.key, required this.state, this.size = 160});

  final TinTinState state;
  final double size;

  static const Duration cycle = Duration(milliseconds: 1200);
  static const int cycles = 3;

  static String semanticsLabel(TinTinState s) => switch (s) {
    TinTinState.idle => 'Tin Tin đang chờ em',
    TinTinState.happy => 'Tin Tin đang vui',
    TinTinState.sad => 'Tin Tin đang buồn',
    TinTinState.cheer => 'Tin Tin đang reo mừng',
    TinTinState.dance => 'Tin Tin đang nhảy múa',
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semanticsLabel(state),
      image: true,
      excludeSemantics: true,
      child: _TinTinBody(key: ValueKey(state), state: state, size: size),
    );
  }
}

class _TinTinBody extends StatefulWidget {
  const _TinTinBody({super.key, required this.state, required this.size});
  final TinTinState state;
  final double size;

  @override
  State<_TinTinBody> createState() => _TinTinBodyState();
}

class _TinTinBodyState extends State<_TinTinBody>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: TinTin.cycle,
  );

  bool get _animated =>
      widget.state == TinTinState.cheer || widget.state == TinTinState.dance;

  @override
  void initState() {
    super.initState();
    if (_animated) _c.repeat(count: TinTin.cycles);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => CustomPaint(
          painter: _TinTinPainter(widget.state, _animated ? _c.value : 0),
        ),
      ),
    );
  }
}

class _TinTinPainter extends CustomPainter {
  _TinTinPainter(this.state, this.t);
  final TinTinState state;
  final double t; // 0..1 within a cycle

  static const _body = Color(0xFF7FD6C2);
  static const _belly = Color(0xFFE8FFF8);
  static const _ink = Color(0xFF14123A);
  static const _cheek = Color(0xFFFF8FB8);

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final phase = math.sin(t * 2 * math.pi);
    final bounce = state == TinTinState.idle ? 0.0 : -phase.abs() * s * 0.06;
    final tilt = state == TinTinState.dance ? phase * 0.12 : 0.0;

    canvas.save();
    canvas.translate(s / 2, s * 0.55 + bounce);
    canvas.rotate(tilt);
    canvas.translate(-s / 2, -s * 0.55);

    final fill = Paint()..color = _body;
    final earDroop = state == TinTinState.sad ? 0.35 : 0.0;
    for (final side in [-1.0, 1.0]) {
      canvas.save();
      canvas.translate(s / 2 + side * s * 0.2, s * 0.3);
      canvas.rotate(
        side *
            (0.25 + earDroop + (state == TinTinState.cheer ? phase * 0.15 : 0)),
      );
      final ear = Rect.fromCenter(
        center: Offset(0, -s * 0.16),
        width: s * 0.16,
        height: s * 0.42,
      );
      canvas.drawOval(ear, fill);
      canvas.drawOval(
        ear.deflate(s * 0.03),
        Paint()..color = _cheek.withValues(alpha: 0.6),
      );
      canvas.restore();
    }

    canvas.drawCircle(Offset(s / 2, s * 0.58), s * 0.36, fill);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset(s / 2, s * 0.7),
        width: s * 0.42,
        height: s * 0.3,
      ),
      Paint()..color = _belly,
    );

    final ink = Paint()..color = _ink;
    final eyeY = s * 0.5;
    for (final side in [-1.0, 1.0]) {
      final c = Offset(s / 2 + side * s * 0.14, eyeY);
      switch (state) {
        case TinTinState.happy:
        case TinTinState.cheer:
          canvas.drawArc(
            Rect.fromCenter(center: c, width: s * 0.12, height: s * 0.1),
            math.pi,
            math.pi,
            false,
            Paint()
              ..color = _ink
              ..style = PaintingStyle.stroke
              ..strokeWidth = s * 0.025
              ..strokeCap = StrokeCap.round,
          );
        case TinTinState.sad:
          canvas.drawCircle(c, s * 0.04, ink);
          canvas.drawLine(
            c.translate(-side * s * 0.05, -s * 0.07),
            c.translate(side * s * 0.05, -s * 0.09 + s * 0.04),
            Paint()
              ..color = _ink
              ..strokeWidth = s * 0.02
              ..strokeCap = StrokeCap.round,
          );
        case TinTinState.idle:
        case TinTinState.dance:
          canvas.drawCircle(c, s * 0.045, ink);
          canvas.drawCircle(
            c.translate(s * 0.012, -s * 0.012),
            s * 0.014,
            Paint()..color = Colors.white,
          );
      }
      canvas.drawCircle(
        Offset(s / 2 + side * s * 0.23, s * 0.58),
        s * 0.05,
        Paint()..color = _cheek,
      );
    }

    final mouthC = Offset(s / 2, s * 0.6);
    final stroke = Paint()
      ..color = _ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = s * 0.025
      ..strokeCap = StrokeCap.round;
    switch (state) {
      case TinTinState.idle:
        canvas.drawArc(
          Rect.fromCenter(center: mouthC, width: s * 0.12, height: s * 0.07),
          0.1,
          math.pi - 0.2,
          false,
          stroke,
        );
      case TinTinState.happy:
        canvas.drawArc(
          Rect.fromCenter(center: mouthC, width: s * 0.18, height: s * 0.12),
          0.1,
          math.pi - 0.2,
          false,
          stroke,
        );
      case TinTinState.cheer:
      case TinTinState.dance:
        canvas.drawArc(
          Rect.fromCenter(center: mouthC, width: s * 0.2, height: s * 0.16),
          0,
          math.pi,
          true,
          ink,
        );
      case TinTinState.sad:
        canvas.drawArc(
          Rect.fromCenter(
            center: mouthC.translate(0, s * 0.04),
            width: s * 0.14,
            height: s * 0.08,
          ),
          math.pi + 0.2,
          math.pi - 0.4,
          false,
          stroke,
        );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_TinTinPainter old) => old.state != state || old.t != t;
}
