import 'package:flutter/material.dart';

import 'space_pup_painter.dart';

enum TinTinState { idle, happy, sad, cheer, dance }

/// Tin Tin, the Space Puppy mascot, drawn with [CustomPaint].
///
/// cheer/dance play a short bounded animation: [cycles] cycles of [cycle]
/// (1.2 s, below the 1.5 s cap, ~0.8 Hz so nothing flashes above 3 Hz) and
/// then rest. Other states are static.
class TinTin extends StatelessWidget {
  const TinTin({
    super.key,
    required this.state,
    this.size = 160,
    this.pulse = 0,
  });

  final TinTinState state;
  final double size;

  /// Change this to replay cheer/dance when the state stays the same.
  final int pulse;

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
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Semantics(
      label: semanticsLabel(state),
      image: true,
      excludeSemantics: true,
      child: RepaintBoundary(
        child: _TinTinBody(
          key: ValueKey((state, pulse, reduce)),
          state: state,
          size: size,
          animate: !reduce,
        ),
      ),
    );
  }
}

class _TinTinBody extends StatefulWidget {
  const _TinTinBody({
    super.key,
    required this.state,
    required this.size,
    required this.animate,
  });
  final TinTinState state;
  final double size;
  final bool animate;

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
      widget.animate &&
      (widget.state == TinTinState.cheer || widget.state == TinTinState.dance);

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
          painter: SpacePupPainter(
            state: widget.state,
            t: _animated ? _c.value : 0,
          ),
        ),
      ),
    );
  }
}
