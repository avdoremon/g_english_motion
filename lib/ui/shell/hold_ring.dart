import 'package:flutter/widgets.dart';

import 'hold_ring_painter.dart';

/// The hand cursor of the hold-to-pick modes: a ring around the hand position
/// that fills (0..1 [progress]) while the hand stays on one target.
///
/// Decorative: it is excluded from semantics and never takes pointer events.
class HoldRing extends StatelessWidget {
  const HoldRing({super.key, required this.progress, this.size = 56});

  final double progress;
  final double size;

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: IgnorePointer(
        child: RepaintBoundary(
          child: CustomPaint(
            size: Size.square(size),
            painter: HoldRingPainter(progress: progress),
          ),
        ),
      ),
    );
  }
}
