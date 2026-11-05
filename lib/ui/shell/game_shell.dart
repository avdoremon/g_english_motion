import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../audio/audio_service.dart';
import '../../input/game_input_event.dart';
import '../../progress/progress_store.dart';
import '../../session/pausable_session.dart';
import 'pause_overlay.dart';
import 'play_surface.dart';

export '../../session/pausable_session.dart';
export 'play_surface.dart' show BreakTimerFactory;

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

/// Wraps the playing area of a CAMERA play flow: wakelock, the pose camera
/// host, lifecycle + player-lost pausing, and - through [PlaySurface] - the
/// caption strip and the "take a break" reminder after every [breakAfter] of
/// play time (the clock stops while the session is paused, and what was
/// played is banked in [store], so going Home between two short levels does
/// not restart the 20 minutes).
///
/// The session is running only while the app is active AND the player is in
/// frame AND no modal ([pausedByDialog]) or break reminder is up;
/// pause()/resume() are called only on changes of that state.
///
/// [timerFactory] is compared by identity: pass a stable reference (a
/// tear-off or field), not a fresh closure per build, or the break clock
/// restarts on every rebuild.
///
/// [events]/[session] may be swapped (didUpdateWidget resubscribes / pauses a
/// new session if currently not running). Changing [breakAfter] or
/// [timerFactory] restarts the break clock.
class GameShell extends StatefulWidget {
  const GameShell({
    super.key,
    required this.child,
    required this.events,
    required this.audio,
    this.session,
    this.store,
    this.wakelock = const WakelockPlusAdapter(),
    this.breakAfter = const Duration(minutes: 20),
    this.timerFactory = Timer.new,
    this.elapsed = _monotonic,
    this.showBanner = false,
    this.pausedByDialog = false,
    this.captionFilter,
    this.captionReset,
    this.cameraHost,
  });

  final Widget child;
  final PausableSession? session;
  final Stream<GameInputEvent> events;
  final AudioService audio;
  final Wakelock wakelock;

  /// Where play time is banked between play flows (null: not counted).
  final ProgressStore? store;
  final Duration breakAfter;
  final BreakTimerFactory timerFactory;

  /// Monotonic clock used to measure play time (injectable for tests).
  final Duration Function() elapsed;
  final bool showBanner;

  /// The app has a modal open over the game (the "leave the game?"
  /// confirmation): the session is paused for as long as it is, so the
  /// question cannot time out and no jump is graded while a grown-up reads
  /// the dialog. It goes through the same pause/resume pairing as a lost
  /// player, so the two can never unpause each other.
  final bool pausedByDialog;

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
  bool _playerLost = false;
  bool _breakVisible = false;
  bool _appActive =
      (WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed) ==
      AppLifecycleState.resumed;
  late bool _wasRunning;

  bool get _running =>
      _appActive && !_playerLost && !_breakVisible && !widget.pausedByDialog;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_enableWakelock());
    _sub = widget.events.listen(_onEvent);
    _wasRunning = _running;
  }

  Future<void> _enableWakelock() async {
    try {
      await widget.wakelock.enable();
    } catch (_) {
      // Keeping the screen awake is best effort.
    }
  }

  /// Applies a change of app / player / dialog / break state, calling the
  /// session only when the running state actually flips. The break clock
  /// itself follows [PlaySurface.paused].
  void _update({bool? appActive, bool? playerLost}) {
    if (appActive != null) _appActive = appActive;
    if (playerLost != null && playerLost != _playerLost) {
      setState(() => _playerLost = playerLost);
    }
    final after = _running;
    if (after == _wasRunning) return;
    // Rebuild so PlaySurface sees the new `paused`: the break clock follows
    // it, and only some of the callers above set state themselves.
    if (mounted) setState(() => _wasRunning = after);
    if (after) {
      widget.session?.resume();
    } else {
      widget.session?.pause();
    }
  }

  void _onBreakDue() {
    if (!mounted) return;
    setState(() => _breakVisible = true);
    _update();
  }

  void _dismissBreak() {
    if (!mounted || !_breakVisible) return;
    setState(() => _breakVisible = false);
    _update();
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
    if (old.pausedByDialog != widget.pausedByDialog) _update();
    if (old.session != widget.session && !_running) {
      widget.session?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    unawaited(widget.wakelock.disable());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Every child is keyed: when the overlay appears/disappears Flutter
    // matches children by key, so the camera host's element (and its single
    // platform view) is never re-paired with another widget and re-created.
    return Stack(
      children: [
        Positioned.fill(
          key: const ValueKey('shell-content'),
          child: PlaySurface(
            audio: widget.audio,
            store: widget.store,
            breakAfter: widget.breakAfter,
            timerFactory: widget.timerFactory,
            elapsed: widget.elapsed,
            showBanner: widget.showBanner,
            captionFilter: widget.captionFilter,
            captionReset: widget.captionReset,
            paused: !_running,
            breakVisible: _breakVisible,
            onBreakDue: _onBreakDue,
            onDismissBreak: _dismissBreak,
            overlay: _playerLost
                ? const PauseOverlay(
                    key: ValueKey('shell-pause-overlay'),
                    message: 'Em đâu rồi? Quay lại khung hình nhé',
                  )
                : null,
            child: widget.child,
          ),
        ),
        if (widget.cameraHost case final host?)
          Positioned(
            key: const ValueKey('shell-camera-host'),
            left: 0,
            bottom: 0,
            child: host,
          ),
      ],
    );
  }
}
