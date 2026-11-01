import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../audio/audio_service.dart';
import '../../audio/voice_lines.dart';
import '../../input/game_input_event.dart';
import '../../session/pausable_session.dart';
import 'banner_slot.dart';
import 'pause_overlay.dart';

export '../../session/pausable_session.dart';

/// Keeps the screen awake while playing.
abstract interface class Wakelock {
  Future<void> enable();
  Future<void> disable();
}

class WakelockPlusAdapter implements Wakelock {
  const WakelockPlusAdapter();
  @override
  Future<void> enable() => WakelockPlus.enable();
  @override
  Future<void> disable() => WakelockPlus.disable();
}

typedef BreakTimerFactory = Timer Function(Duration d, void Function() cb);

/// Wraps the playing area: wakelock, lifecycle + player-lost pausing, and a
/// single "take a break" reminder after [breakAfter] of play.
///
/// [events] and [session] are read once at init.
class GameShell extends StatefulWidget {
  const GameShell({
    super.key,
    required this.child,
    required this.events,
    required this.audio,
    this.session,
    this.wakelock = const WakelockPlusAdapter(),
    this.breakAfter = const Duration(minutes: 20),
    this.timerFactory = Timer.new,
    this.showBanner = false,
  });

  final Widget child;
  final PausableSession? session;
  final Stream<GameInputEvent> events;
  final AudioService audio;
  final Wakelock wakelock;
  final Duration breakAfter;
  final BreakTimerFactory timerFactory;
  final bool showBanner;

  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> with WidgetsBindingObserver {
  StreamSubscription<GameInputEvent>? _sub;
  Timer? _breakTimer;
  bool _playerLost = false;
  bool _breakShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(widget.wakelock.enable());
    _sub = widget.events.listen(_onEvent);
    _breakTimer = widget.timerFactory(widget.breakAfter, _onBreak);
  }

  void _onBreak() {
    if (_breakShown || !mounted) return;
    _breakShown = true;
    unawaited(widget.audio.playLine(VoiceLine.takeABreak));
  }

  void _onEvent(GameInputEvent e) {
    if (e is PlayerLost && !_playerLost) {
      setState(() => _playerLost = true);
      widget.session?.pause();
    } else if (e is PlayerFound && _playerLost) {
      setState(() => _playerLost = false);
      widget.session?.resume();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        // Stay paused while the player is out of frame.
        if (!_playerLost) widget.session?.resume();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        widget.session?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    _breakTimer?.cancel();
    unawaited(widget.wakelock.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: Column(
            children: [
              Expanded(child: widget.child),
              if (widget.showBanner) const BannerSlot(),
            ],
          ),
        ),
        if (_playerLost)
          const Positioned.fill(
            child: PauseOverlay(message: 'Em đâu rồi? Quay lại khung hình nhé'),
          ),
      ],
    );
  }
}
