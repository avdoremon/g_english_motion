import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../audio/audio_service.dart';
import '../../audio/voice_lines.dart';
import '../../progress/progress_store.dart';
import 'banner_slot.dart';
import 'break_reminder.dart';
import 'caption_strip.dart';

typedef BreakTimerFactory = Timer Function(Duration d, void Function() cb);

final Stopwatch _sw = Stopwatch()..start();
Duration _monotonic() => _sw.elapsed;

/// The services every play surface needs, with NO camera and NO pose source:
/// the caption strip under the playing area (every spoken line must also be
/// readable) and the "take a break" clock.
///
/// [GameShell] adds the camera host and the pose-driven pausing on top of
/// this; SayIt uses it on its own, so its spoken lines are captioned and its
/// play time counts towards the same break reminder.
///
/// The host owns the paused/break state, so there is one source of truth:
/// - [paused]: the play clock stands still (app in the background, player out
///   of frame, a modal open, or the break reminder up). The time played so
///   far is banked in [store].
/// - [onBreakDue]: the clock reached [breakAfter]. The host shows the
///   reminder by passing [breakVisible] and pausing whatever it drives.
/// - [breakVisible] + [onDismissBreak]: draws [BreakReminder] over the
///   playing area (never over the captions) until a grown-up dismisses it.
///
/// [timerFactory] is compared by identity: pass a stable reference, not a
/// fresh closure per build, or the break clock restarts on every rebuild.
class PlaySurface extends StatefulWidget {
  const PlaySurface({
    super.key,
    required this.child,
    required this.audio,
    this.store,
    this.breakAfter = const Duration(minutes: 20),
    this.timerFactory = Timer.new,
    this.elapsed = _monotonic,
    this.showBanner = false,
    this.captionFilter,
    this.captionReset,
    this.overlay,
    this.paused = false,
    this.breakVisible = false,
    this.onBreakDue,
    this.onDismissBreak,
  });

  final Widget child;
  final AudioService audio;

  /// Where play time is banked across play flows (null: not counted, e.g. in
  /// widget tests of a single screen).
  final ProgressStore? store;

  final Duration breakAfter;
  final BreakTimerFactory timerFactory;

  /// Monotonic clock used to measure play time (injectable for tests).
  final Duration Function() elapsed;
  final bool showBanner;

  /// Captions for which this returns false are not shown in the strip.
  final bool Function(String caption)? captionFilter;

  /// Notifies when the caption strip should be emptied (new question).
  final Listenable? captionReset;

  /// The host's own overlay above the playing area (e.g. "come back into
  /// frame"), below the break reminder.
  final Widget? overlay;

  final bool paused;
  final bool breakVisible;
  final VoidCallback? onBreakDue;
  final VoidCallback? onDismissBreak;

  @override
  State<PlaySurface> createState() => _PlaySurfaceState();
}

class _PlaySurfaceState extends State<PlaySurface> {
  Timer? _breakTimer;
  Duration? _armedAt;
  late Duration _remaining;

  /// The play clock runs unless the host paused it.
  bool get _running => !widget.paused;

  @override
  void initState() {
    super.initState();
    // Carries over what earlier play flows already banked: the shell is
    // rebuilt per flow, the 20 minutes are not.
    final played = widget.store?.playedTowardsBreak() ?? Duration.zero;
    _remaining = widget.breakAfter - played;
    if (_remaining < Duration.zero) _remaining = Duration.zero;
    if (_running) _armBreak();
  }

  void _armBreak() {
    _breakTimer?.cancel();
    _breakTimer = null;
    if (!_running) return;
    _armedAt = widget.elapsed();
    _breakTimer = widget.timerFactory(_remaining, _onBreak);
  }

  /// Stops the clock, banking the time played since it was armed.
  void _disarmBreak() {
    if (_breakTimer == null) return;
    _breakTimer!.cancel();
    _breakTimer = null;
    final spent = widget.elapsed() - _armedAt!;
    _remaining -= spent;
    if (_remaining < Duration.zero) _remaining = Duration.zero;
    _bank(spent);
  }

  void _bank(Duration spent) {
    if (spent <= Duration.zero) return;
    final store = widget.store;
    if (store == null) return;
    unawaited(store.addPlayTime(spent).catchError((Object _) {}));
  }

  void _onBreak() {
    if (!mounted) return;
    final spent = widget.elapsed() - (_armedAt ?? widget.elapsed());
    _breakTimer = null;
    _bank(spent);
    final store = widget.store;
    if (store != null) {
      unawaited(store.resetPlayTime().catchError((Object _) {}));
    }
    // Re-armed for the NEXT twenty minutes: the spec asks for a reminder
    // after every 20 minutes of play, not once per app session.
    _remaining = widget.breakAfter;
    // Self-sufficient: re-arm here instead of relying on the host to toggle
    // [PlaySurface.paused] (a host that does pause simply disarms it again).
    if (_running) _armBreak();
    unawaited(widget.audio.playLine(VoiceLine.takeABreak));
    widget.onBreakDue?.call();
  }

  @override
  void didUpdateWidget(PlaySurface old) {
    super.didUpdateWidget(old);
    if (old.breakAfter != widget.breakAfter ||
        old.timerFactory != widget.timerFactory) {
      _breakTimer?.cancel();
      _breakTimer = null;
      _remaining = widget.breakAfter;
      if (_running) _armBreak();
      return;
    }
    if (old.paused != widget.paused) {
      if (_running) {
        _armBreak();
      } else {
        _disarmBreak();
      }
    }
  }

  @override
  void dispose() {
    // Leaving the play flow: bank what was played, so the next flow
    // continues the same 20 minutes instead of starting over.
    _disarmBreak();
    _breakTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // The overlays cover the playing area only: the caption strip below
        // stays readable, so a line spoken while the game is paused can
        // still be read.
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                key: const ValueKey('play-area'),
                child: widget.child,
              ),
              if (widget.overlay case final o?)
                Positioned.fill(key: const ValueKey('play-overlay'), child: o),
              if (widget.breakVisible)
                Positioned.fill(
                  key: const ValueKey('break-reminder'),
                  child: BreakReminder(
                    onDismiss: widget.onDismissBreak ?? () {},
                  ),
                ),
            ],
          ),
        ),
        CaptionStrip(
          captions: widget.audio.captions,
          filter: widget.captionFilter,
          clearOn: widget.captionReset,
        ),
        if (widget.showBanner) const BannerSlot(),
      ],
    );
  }
}
