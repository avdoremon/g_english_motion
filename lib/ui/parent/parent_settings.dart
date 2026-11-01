import 'package:flutter/material.dart';

import '../../input/confirm_gesture.dart';
import '../../progress/progress_store.dart';
import '../theme/app_theme.dart';

class ParentSettings extends StatefulWidget {
  const ParentSettings({
    super.key,
    required this.store,
    required this.grades,
    required this.unitCounts,
  });

  final ProgressStore store;
  final List<int> grades;

  /// Number of units per grade (upper bound of the stepper).
  final Map<int, int> unitCounts;

  @override
  State<ParentSettings> createState() => _ParentSettingsState();
}

class _ParentSettingsState extends State<ParentSettings> {
  ProgressStore get _s => widget.store;

  void _setUnit(int grade, int unit) {
    final max = widget.unitCounts[grade] ?? 1;
    final v = unit.clamp(1, max < 1 ? 1 : max);
    _s.setCurrentUnit(grade, v);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cài đặt cho bố mẹ', style: t.titleLarge),
          const SizedBox(height: 8),
          for (final g in widget.grades)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Lớp $g: bài ${_s.currentUnit(g)}',
                    style: t.titleMedium,
                  ),
                ),
                Semantics(
                  label: 'Giảm bài',
                  button: true,
                  excludeSemantics: true,
                  child: IconButton(
                    key: ValueKey('unit-dec-$g'),
                    tooltip: 'Giảm bài',
                    icon: const Icon(Icons.remove),
                    onPressed: () => _setUnit(g, _s.currentUnit(g) - 1),
                  ),
                ),
                Semantics(
                  label: 'Tăng bài',
                  button: true,
                  excludeSemantics: true,
                  child: IconButton(
                    key: ValueKey('unit-inc-$g'),
                    tooltip: 'Tăng bài',
                    icon: const Icon(Icons.add),
                    onPressed: () => _setUnit(g, _s.currentUnit(g) + 1),
                  ),
                ),
              ],
            ),
          SwitchListTile(
            key: const ValueKey('toggle-no-jump'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Chế độ không nhảy (giơ hai tay)',
              style: t.titleMedium,
            ),
            value: _s.confirmGesture == ConfirmGesture.raiseHands,
            onChanged: (v) {
              _s.setConfirmGesture(
                v ? ConfirmGesture.raiseHands : ConfirmGesture.jump,
              );
              setState(() {});
            },
          ),
          SwitchListTile(
            key: const ValueKey('toggle-sayit'),
            contentPadding: EdgeInsets.zero,
            title: Text('Đọc to từ vựng', style: t.titleMedium),
            value: _s.sayItEnabled,
            onChanged: (v) {
              _s.setSayItEnabled(v);
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          // Placeholder: the policy text is bundled locally later (no network).
          Text(
            'Chính sách quyền riêng tư',
            style: t.bodyMedium?.copyWith(
              color: AppTheme.accent,
              decoration: TextDecoration.underline,
            ),
          ),
        ],
      ),
    );
  }
}
