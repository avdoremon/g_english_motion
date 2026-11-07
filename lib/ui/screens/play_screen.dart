import 'package:flutter/material.dart';

import '../../app/game_controller.dart';
import '../../content/models.dart';
import '../../session/level_session.dart';
import 'balloon_pop_screen.dart';
import 'drag_spell_screen.dart';
import 'lane_jump_screen.dart';
import 'memory_flip_screen.dart';
import 'sky_shoot_screen.dart';

/// The play screen of the current question's mode: a level of grades 3-5
/// mixes modes, so the screen follows the question, not the grade.
class PlayScreen extends StatelessWidget {
  const PlayScreen({super.key, required this.controller, this.onExit});

  final GameController controller;
  final VoidCallback? onExit;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final s = controller.session;
        if (s == null || s.phase == SessionPhase.finished) {
          return const SizedBox.shrink();
        }
        return switch (s.current.mode) {
          ModeKind.dragSpell => DragSpellScreen(
            key: const ValueKey('mode-dragSpell'),
            controller: controller,
            onExit: onExit,
          ),
          ModeKind.skyShoot => SkyShootScreen(
            key: const ValueKey('mode-skyShoot'),
            controller: controller,
            onExit: onExit,
          ),
          ModeKind.memoryFlip => MemoryFlipScreen(
            key: const ValueKey('mode-memoryFlip'),
            controller: controller,
            onExit: onExit,
          ),
          ModeKind.balloonPop => BalloonPopScreen(
            key: const ValueKey('mode-balloonPop'),
            controller: controller,
            onExit: onExit,
          ),
          _ => LaneJumpScreen(
            key: const ValueKey('mode-laneJump'),
            controller: controller,
            onExit: onExit,
          ),
        };
      },
    );
  }
}
