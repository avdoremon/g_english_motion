/// Progress of holding the cursor on one target.
class HoldProgress {
  const HoldProgress({
    required this.targetId,
    required this.progress,
    required this.completed,
  });

  /// The target being held (null: none).
  final String? targetId;

  /// 0..1 fraction of the hold time.
  final double progress;

  /// True on exactly one update: the one that completes the hold.
  final bool completed;
}

/// Times how long the cursor stays on a target.
///
/// Leaving the target for less than [grace] keeps the progress (landmark
/// jitter); leaving for [grace] or longer, or moving to another target,
/// starts over. After completing, the same target does not complete again
/// until the cursor has left it (for at least [grace]) or [reset] was called.
/// All times are caller-supplied (frame/tick timestamps), never wall-clock.
class HoldTracker {
  HoldTracker({
    this.holdTime = const Duration(seconds: 1),
    this.grace = const Duration(milliseconds: 200),
  });

  final Duration holdTime;
  final Duration grace;

  String? _target;
  Duration _held = Duration.zero;

  /// Last update that was on the target.
  Duration? _lastOn;

  /// An update without the target came in since [_lastOn].
  bool _away = false;
  bool _done = false;

  void reset() {
    _target = null;
    _held = Duration.zero;
    _lastOn = null;
    _away = false;
    _done = false;
  }

  HoldProgress update(String? targetId, Duration now) {
    if (targetId == null) {
      final last = _lastOn;
      if (_target == null || last == null) return _idle();
      if (now - last >= grace) {
        reset();
        return _idle();
      }
      _away = true;
      return _report();
    }
    if (targetId != _target) {
      // A new target (or the first one): start over.
      reset();
      _target = targetId;
      _lastOn = now;
      return _report();
    }
    final last = _lastOn!;
    if (_away) {
      if (now - last >= grace) {
        // Away for too long (the away update may have been the last one).
        _held = Duration.zero;
        _done = false;
      }
      // A short dropout is neither counted nor lost.
      _away = false;
    } else if (!_done && now > last) {
      _held += now - last;
    }
    _lastOn = now;
    if (!_done && _held >= holdTime) {
      _done = true;
      _held = holdTime;
      return HoldProgress(targetId: _target, progress: 1, completed: true);
    }
    return _report();
  }

  HoldProgress _report() => HoldProgress(
    targetId: _target,
    progress: _done || holdTime <= Duration.zero
        ? 1
        : (_held.inMicroseconds / holdTime.inMicroseconds).clamp(0.0, 1.0),
    completed: false,
  );

  HoldProgress _idle() =>
      const HoldProgress(targetId: null, progress: 0, completed: false);
}
