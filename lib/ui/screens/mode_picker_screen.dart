import 'package:flutter/material.dart';

import '../../content/models.dart';
import '../../modes/mode_availability.dart';
import '../kit/kit.dart';
import '../theme/app_theme.dart';

/// "Chọn trò chơi": a 3-column grid with one tile per mode plus a shuffle
/// tile. Tiles not offered at [grade] stay visible but disabled and say which
/// grades they are for. The choice is session state only (nothing is stored).
///
/// SayIt is listed only when [sayItAvailable] (the same condition under which
/// Home shows "Luyện nói"); the app starts it through its own SayIt path.
class ModePickerScreen extends StatelessWidget {
  const ModePickerScreen({
    super.key,
    required this.grade,
    required this.level,
    required this.onPick,
    required this.onBack,
    this.sayItAvailable = false,
  });

  final int grade, level;

  /// `null` means "Trộn ngẫu nhiên": every camera mode valid for the grade.
  final void Function(ModeKind? mode) onPick;
  final VoidCallback onBack;
  final bool sayItAvailable;

  static const _columns = 3;
  static const _gap = 14.0;
  static const _tileHeight = 96.0;

  /// Body-driven modes use the whole body, hand modes the hand cursor.
  static IconData inputIcon(ModeInfo i) {
    if (!i.usesCamera) return Icons.mic;
    switch (i.mode) {
      case ModeKind.laneJump:
      case ModeKind.catchIt:
        return Icons.accessibility_new;
      default:
        return Icons.back_hand;
    }
  }

  static String gradeRange(ModeInfo i) => i.minGrade == i.maxGrade
      ? 'Lớp ${i.minGrade}'
      : 'Lớp ${i.minGrade}–${i.maxGrade}';

  @override
  Widget build(BuildContext context) {
    final infos = [
      for (final i in kModeInfos)
        if (i.mode != ModeKind.sayIt || sayItAvailable) i,
    ];
    final valid = modesForGrade(grade);
    final tiles = <Widget>[
      for (final i in infos)
        _ModeTile(
          key: ValueKey('mode-${i.mode.name}'),
          title: i.title,
          detail: gradeRange(i),
          icon: valid.contains(i.mode) ? inputIcon(i) : Icons.lock_outline,
          semanticLabel: valid.contains(i.mode)
              ? i.title
              : '${i.title}, chỉ có ở ${gradeRange(i).toLowerCase()}',
          onTap: valid.contains(i.mode) ? () => onPick(i.mode) : null,
        ),
      _ModeTile(
        key: const ValueKey('mode-shuffle'),
        title: 'Trộn ngẫu nhiên',
        detail: 'Lớp $grade',
        icon: Icons.shuffle,
        semanticLabel: 'Trộn ngẫu nhiên các trò chơi',
        highlight: true,
        onTap: () => onPick(null),
      ),
    ];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(
          children: [
            Row(
              children: [
                RoundIconButton(
                  key: const ValueKey('picker-back'),
                  icon: Icons.arrow_back,
                  semanticLabel: 'Quay lại',
                  onPressed: onBack,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Chọn trò chơi',
                      maxLines: 1,
                      style: AppTheme.textStyles.heading,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final w = (box.maxWidth - _gap * (_columns - 1)) / _columns;
                  // Scrolls on short screens instead of overflowing.
                  return SingleChildScrollView(
                    child: Wrap(
                      spacing: _gap,
                      runSpacing: _gap,
                      children: [
                        for (final t in tiles)
                          SizedBox(width: w, height: _tileHeight, child: t),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  const _ModeTile({
    super.key,
    required this.title,
    required this.detail,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.highlight = false,
  });

  final String title, detail, semanticLabel;
  final IconData icon;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = highlight ? AppTheme.ink : AppTheme.text;
    return Semantics(
      button: true,
      enabled: enabled,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Opacity(
        opacity: enabled ? 1 : 0.5,
        child: Material(
          color: Colors.transparent,
          child: Ink(
            decoration: BoxDecoration(
              color: highlight ? AppTheme.yellow : AppTheme.surfaceLight,
              borderRadius: BorderRadius.circular(24),
              boxShadow: const [
                BoxShadow(color: AppTheme.ink, offset: Offset(0, 5)),
              ],
            ),
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Icon(icon, size: 32, color: fg),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              title,
                              maxLines: 1,
                              style: AppTheme.textStyles.play.copyWith(
                                color: fg,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              detail,
                              maxLines: 1,
                              style: AppTheme.textStyles.label.copyWith(
                                color: highlight
                                    ? AppTheme.ink
                                    : AppTheme.muted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
