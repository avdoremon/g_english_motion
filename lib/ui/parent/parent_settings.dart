import '../theme/app_theme.dart';

import 'dart:async';

import 'package:flutter/material.dart';

import '../../content/content_repository.dart';
import '../../input/confirm_gesture.dart';
import '../../progress/progress_store.dart';

class ParentSettings extends StatefulWidget {
  const ParentSettings({
    super.key,
    required this.store,
    required this.grades,
    required this.unitCounts,
    this.onSayItTurnedOn,
  });

  /// Settings for every grade (1-5) with the unit counts of [repo].
  ParentSettings.forRepo({
    Key? key,
    required ProgressStore store,
    required ContentRepository repo,
    Future<void> Function()? onSayItTurnedOn,
  }) : this(
         key: key,
         store: store,
         grades: const [1, 2, 3, 4, 5],
         unitCounts: {
           for (final g in const [1, 2, 3, 4, 5]) g: repo.unitsFor(g).length,
         },
         onSayItTurnedOn: onSayItTurnedOn,
       );

  /// Called when the parent switches SayIt on: the place to ask for the
  /// microphone (this screen is behind the parent gate).
  final Future<void> Function()? onSayItTurnedOn;

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

  /// One semantics node (label + tap) with a visible tooltip: the Tooltip's
  /// own semantics are excluded so the label is not announced twice.
  Widget _stepper({
    required String label,
    required Key key,
    required IconData icon,
    required VoidCallback onPressed,
  }) {
    return MergeSemantics(
      child: Semantics(
        label: label,
        child: Tooltip(
          message: label,
          excludeFromSemantics: true,
          child: IconButton(key: key, icon: Icon(icon), onPressed: onPressed),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Cài đặt cho bố mẹ', style: AppTheme.textStyles.heading),
          const SizedBox(height: 8),
          for (final g in widget.grades)
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Lớp $g: bài ${_s.currentUnit(g)}',
                    style: AppTheme.textStyles.label,
                  ),
                ),
                _stepper(
                  label: 'Giảm bài lớp $g',
                  key: ValueKey('unit-dec-$g'),
                  icon: Icons.remove,
                  onPressed: () => _setUnit(g, _s.currentUnit(g) - 1),
                ),
                _stepper(
                  label: 'Tăng bài lớp $g',
                  key: ValueKey('unit-inc-$g'),
                  icon: Icons.add,
                  onPressed: () => _setUnit(g, _s.currentUnit(g) + 1),
                ),
              ],
            ),
          SwitchListTile(
            key: const ValueKey('toggle-no-jump'),
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Chế độ không nhảy (giơ hai tay)',
              style: AppTheme.textStyles.label,
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
            title: Text('Đọc to từ vựng', style: AppTheme.textStyles.label),
            value: _s.sayItEnabled,
            onChanged: (v) {
              _s.setSayItEnabled(v);
              if (v) unawaited(widget.onSayItTurnedOn?.call());
              setState(() {});
            },
          ),
          const SizedBox(height: 8),
          // A plain line, not a link: there is no policy page to open yet,
          // and a line that looks tappable but does nothing reads as a bug.
          // When the policy ships it will be a bundled local asset (no
          // network) opened from a real button here.
          Text(
            'Chính sách quyền riêng tư: ứng dụng không gửi dữ liệu đi đâu. '
            'Hình ảnh camera và âm thanh micro chỉ được xử lý trên máy này '
            'và không được lưu lại.',
            style: AppTheme.textStyles.label.copyWith(color: AppTheme.muted),
          ),
        ],
      ),
    );
  }
}
