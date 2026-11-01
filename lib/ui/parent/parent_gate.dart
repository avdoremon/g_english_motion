import 'dart:math';

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class GateQuestion {
  const GateQuestion(this.a, this.b);
  final int a;
  final int b;
  int get answer => a * b;
}

/// Adult-only gate: a multiplication question answered on a number pad.
class ParentGate extends StatefulWidget {
  const ParentGate({super.key, required this.child, this.rng});

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
  late final GateQuestion _q = ParentGate.questionFor(widget.rng ?? Random());
  late final AnimationController _shake = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600), // 1.5 cycles: < 3 Hz
  );
  String _entry = '';
  bool _open = false;
  bool _wrong = false;

  @override
  void dispose() {
    _shake.dispose();
    super.dispose();
  }

  void _submit() {
    if (_entry == '${_q.answer}') {
      setState(() => _open = true);
    } else {
      setState(() {
        _wrong = true;
        _entry = '';
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
        ),
        onPressed: onTap,
        child: label,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    if (_open) return widget.child;
    final t = Theme.of(context).textTheme;
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
            Text('Dành cho bố mẹ', style: t.bodyMedium),
            const SizedBox(height: 8),
            Text('${_q.a} × ${_q.b} = ?', style: t.titleLarge),
            AnimatedBuilder(
              animation: _shake,
              builder: (context, child) => Transform.translate(
                offset: Offset(sin(_shake.value * 3 * pi) * 10, 0),
                child: child,
              ),
              child: SizedBox(
                height: 48,
                child: Text(
                  _wrong ? 'Chưa đúng' : (_entry.isEmpty ? ' ' : _entry),
                  style: t.titleMedium?.copyWith(
                    color: _wrong ? AppTheme.pink : AppTheme.text,
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
                _key('back', const Icon(Icons.backspace_outlined), () {
                  if (_entry.isNotEmpty) {
                    setState(
                      () => _entry = _entry.substring(0, _entry.length - 1),
                    );
                  }
                }),
                digit('0'),
                _key('ok', const Icon(Icons.check), _submit),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
