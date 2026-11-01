import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../audio/audio_service.dart';
import '../../audio/voice_lines.dart';
import '../../input/game_input_event.dart';
import '../../session/pausable_session.dart';
import 'banner_slot.dart';
import 'caption_strip.dart';
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

final Stopwatch _sw = Stopwatch()..start();
Duration _monotonic() => _sw.elapsed;

typedef BreakTimerFactory = Timer Function(Duration d, void Function() cb);

/// Wraps the playing area: wakelock, a caption strip (what the voice says), lifecycle + player-lost pausing, and a
/// single "take a break" reminder after [breakAfter] of PLAY time (the clock
/// stops while the session is paused and resumes with the remaining time).
///
/// The session is running only while the app is active AND the player is in
/// frame; pause()/resume() are called only on changes of that state.
///
/// [timerFactory] is compared by identity: pass a stable reference (a
/// tear-off or field), not a fresh closure per build, or the break clock
/// restarts on every rebuild.
///
/// [events]/[session] may be swapped (didUpdateWidget resubscribes / pauses a
/// new session if currently not running). Changing [breakAfter] or
/// [timerFactory] restarts the break clock; a shell keyed per level therefore
/// restarts the 20-minute clock, so the app must keep ONE shell for the whole
/// play session (Task 14b).
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
    this.elapsed = _monotonic,
    this.showBanner = false,
    this.captionFilter,
    this.captionReset,
    this.cameraHost,
  });

  final Widget child;
  final PausableSession? session;
  final Stream<GameInputEvent> events;
  final AudioService audio;
  final Wakelock wakelock;
  final Duration breakAfter;
  final BreakTimerFactory timerFactory;

  /// Monotonic clock used to measure play time (injectable for tests).
  final Duration Function() elapsed;
  final bool showBanner;

  /// Captions for which this returns false are not shown in the strip.
  final bool Function(String caption)? captionFilter;

  /// Notifies when the caption strip should be emptied (new question).
  final Listenable? captionReset;

  /// The pose plugin's invisible camera host ([PoseCameraHost] in
  /// production, null in tests). Kept for the shell's whole life so the
  /// platform view is created once per play session.
  final Widget? cameraHost;

  @override
  State<GameShell> createState() => _GameShellState();
}

class _GameShellState extends State<GameShell> with WidgetsBindingObserver {
  StreamSubscription<GameInputEvent>? _sub;
  Timer? _breakTimer;
  Duration? _armedAt;
  late Duration _remaining;
  bool _playerLost = false;
  bool _appActive =
      (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
      AppLifecycleState.resumed;
  bool _breakShown = false;

  bool get _running => _appActive && !_playerLost;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enableWakelock());
    _sub = widget.events.listen(_onEvent);
    _remaining = widget.breakAfter;
    _armBreak();
  }

  Future<void> _enableWakelock() async {
    try {
      await widget.wakelock.enable();
    } catch (_) {
      // Keeping the screen awake is best effort.
    }
  }

  void _armBreak() {
    _breakTimer?.cancel();
    _breakTimer = null;
    if (_breakShown) return;
    _armedAt = widget.elapsed();
    _breakTimer = widget.timerFactory(_remaining, _onBreak);
  }

  void _disarmBreak() {
    if (_breakTimer == null) return;
    _breakTimer!.cancel();
    _breakTimer = null;
    final spent = widget.elapsed() - _armedAt!;
    _remaining -= spent;
    if (_remaining < Duration.zero) _remaining = Duration.zero;
  }

  void _onBreak() {
    if (_breakShown || !mounted) return;
    _breakShown = true;
    _breakTimer = null;
    unawaited(widget.audio.playLine(VoiceLine.takeABreak));
  }

  /// Applies a change of app/player state, calling the session only when the
  /// running state actually flips.
  void _update({bool? appActive, bool? playerLost}) {
    final before = _running;
    if (appActive != null) _appActive = appActive;
    if (playerLost != null && playerLost != _playerLost) {
      setState(() => _playerLost = playerLost);
    }
    final after = _running;
    if (before == after) return;
    if (after) {
      widget.session?.resume();
      _armBreak();
    } else {
      widget.session?.pause();
      _disarmBreak();
    }
  }

  void _onEvent(GameInputEvent e) {
    if (e is PlayerLost) {
      _update(playerLost: true);
    } else if (e is PlayerFound) {
      _update(playerLost: false);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _update(appActive: state == AppLifecycleState.resumed);
  }

  @override
  void didUpdateWidget(GameShell old) {
    super.didUpdateWidget(old);
    if (old.events != widget.events) {
      _sub?.cancel();
      _sub = widget.events.listen(_onEvent);
      // A new stream starts with the player assumed present.
      _update(playerLost: false);
    }
    if (old.session != widget.session && !_running) {
      widget.session?.pause();
    }
    if (old.breakAfter != widget.breakAfter ||
        old.timerFactory != widget.timerFactory) {
      _breakTimer?.cancel();
      _breakTimer = null;
      _remaining = widget.breakAfter;
      if (_running) _armBreak();
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
              CaptionStrip(
                captions: widget.audio.captions,
                filter: widget.captionFilter,
                clearOn: widget.captionReset,
              ),
              if (widget.showBanner) const BannerSlot(),
            ],
          ),
        ),
        if (_playerLost)
          const Positioned.fill(
            child: PauseOverlay(message: 'Em đâu rồi? Quay lại khung hình nhé'),
          ),
        if (widget.cameraHost case final host?)
          Positioned(left: 0, bottom: 0, child: host),
      ],
    );
  }
}
