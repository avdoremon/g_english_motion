import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GateQuestion {
  const GateQuestion(this.a, this.b);
  final int a;
  final int b;
  int get answer => a * b;
}

/// Wrong-answer count and lockout of the [ParentGate]. Owned by whoever opens
/// the gate (the app), not by the widget State, so leaving and re-entering the
/// gate cannot be used to reset the count or skip a running lockout.
class GateLockout extends ChangeNotifier {
  GateLockout({this.timerFactory = Timer.new});

  /// Wrong answers allowed before a lockout.
  static const maxWrong = 3;
  static const duration = Duration(seconds: 5);

  /// Injectable for tests.
  final Timer Function(Duration, void Function()) timerFactory;

  int _wrongCount = 0;
  bool _locked = false;
  Timer? _timer;
  bool _disposed = false;

  int get wrongCount => _wrongCount;
  bool get locked => _locked;

  /// Registers a wrong answer; the [maxWrong]th starts the lockout.
  void recordWrong() {
    if (_disposed || _locked) return;
    _wrongCount++;
    if (_wrongCount >= maxWrong) {
      _locked = true;
      _wrongCount = 0;
      _timer = timerFactory(duration, () {
        _timer = null;
        if (_disposed) return;
        _locked = false;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// A right answer clears the count (never an active lockout).
  void recordSuccess() {
    if (_disposed || _locked) return;
    _wrongCount = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}

/// Adult-only gate: a multiplication question answered on a number pad.
class ParentGate extends StatefulWidget {
  const ParentGate({
    super.key,
    required this.child,
    this.rng,
    this.lockout,
    this.timerFactory = Timer.new,
  });

  static const maxWrong = GateLockout.maxWrong;

  /// Count and lockout shared across visits to the gate. When null the gate
  /// keeps its own for its lifetime only (built with [timerFactory]).
  final GateLockout? lockout;

  /// Lockout timer of the gate's own [GateLockout] (tests).
  final Timer Function(Duration, void Function()) timerFactory;

  final Widget child;
  final Random? rng;

  /// 3..9 x 3..9, so answers are always >= 9.
  static GateQuestion questionFor(Random rng) =>
      GateQuestion(3 + rng.nextInt(7), 3 + rng.nextInt(7));

  @override
  State<ParentGate> createState() => _ParentGateState();
}

class _ParentGateState extends State<ParentGate>
    with SingleTickerProviderStateMixin {
  late final Random _rng = widget.rng ?? Random();
  late GateQuestion _q = ParentGate.questionFor(_rng);
  GateLockout? _ownLockout;
  GateLockout get _lock =>
      widget.lockout ??
      (_ownLockout ??= GateLockout(timerFactory: widget.timerFactory));
  bool get _locked => _lock.locked;
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600), // 1.5 cycles: < 3 Hz
  );
  String _entry = '';
  bool _open = false;
  bool _wrong = false;

  @override
  void initState() {
    super.initState();
    _lock.addListener(_onLock);
  }

  @override
  void didUpdateWidget(ParentGate old) {
    super.didUpdateWidget(old);
    if (old.lockout != widget.lockout) {
      (old.lockout ?? _ownLockout)?.removeListener(_onLock);
      _lock.addListener(_onLock);
    }
  }

  void _onLock() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _lock.removeListener(_onLock);
    _ownLockout?.dispose();
    _shake.dispose();
    super.dispose();
  }

  void _submit() {
    if (_locked) return;
    if (_entry == '${_q.answer}') {
      _lock.recordSuccess();
      setState(() => _open = true);
    } else {
      _lock.recordWrong();
      setState(() {
        _wrong = true;
        _entry = '';
        _q = ParentGate.questionFor(_rng);
      });
      _shake.forward(from: 0);
    }
  }

  Widget _key(String id, Widget label, VoidCallback onTap) => Padding(
    padding: const EdgeInsets.all(4),
    child: SizedBox(
      width: 72,
      height: 56,
      child: FilledButton(
        key: ValueKey('key-$id'),
        style: FilledButton.styleFrom(
          minimumSize: const Size(72, 56),
          padding: EdgeInsets.zero,
          backgroundColor: AppTheme.surface,
          foregroundColor: AppTheme.text,
          side: const BorderSide(color: AppTheme.accent, width: 2),
        ),
        onPressed: _locked ? null : onTap,
        child: label,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_open) return widget.child;
    Widget digit(String d) => _key(d, Text(d), () {
      if (_entry.length < 3) {
        setState(() {
          _entry += d;
          _wrong = false;
        });
      }
    });
    return Center(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Dành cho bố mẹ',
              style: AppTheme.textStyles.label.copyWith(color: AppTheme.muted),
            ),
            const SizedBox(height: 8),
            Text('${_q.a} × ${_q.b} = ?', style: AppTheme.textStyles.heading),
            AnimatedBuilder(
              animation: _shake,
              builder: (context, child) => Transform.translate(
                offset: Offset(sin(_shake.value * 3 * pi) * 10, 0),
                child: child,
              ),
              child: SizedBox(
                height: 48,
                child: Text(
                  _locked
                      ? 'Chờ vài giây rồi thử lại'
                      : _wrong
                      ? 'Chưa đúng'
                      : (_entry.isEmpty ? ' ' : _entry),
                  style: AppTheme.textStyles.label.copyWith(
                    color: _wrong ? AppTheme.coral : AppTheme.text,
                  ),
                ),
              ),
            ),
            for (final row in const [
              ['1', '2', '3'],
              ['4', '5', '6'],
              ['7', '8', '9'],
            ])
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [for (final d in row) digit(d)],
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _key(
                  'back',
                  const Icon(Icons.backspace_outlined, semanticLabel: 'Xóa'),
                  () {
                    if (_entry.isNotEmpty) {
                      setState(
                        () => _entry = _entry.substring(0, _entry.length - 1),
                      );
                    }
                  },
                ),
                digit('0'),
                _key(
                  'ok',
                  const Icon(Icons.check, semanticLabel: 'Xác nhận'),
                  _submit,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
