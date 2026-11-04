import 'package:flutter/material.dart';

import '../../progress/progress_store.dart';
import '../../speech/speech_source.dart';
import '../mascot/tin_tin.dart';
import '../theme/app_theme.dart';

/// Home: grade picker, level picker (stars + lock) and the Play button.
///
/// Grades 1-3 are playable (grade 3 has content for units 1-2); grades 4-5 are shown disabled
/// with "Sắp có". The SayIt entry is hidden unless the device can recognise
/// speech on the device ([sayItAvailability] is `available`) and the parent
/// left it enabled.
class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.store,
    required this.sayItAvailability,
    required this.onPlay,
    required this.onSayIt,
    required this.onOpenParent,
  });

  final ProgressStore store;
  final SpeechAvailability sayItAvailability;
  final void Function(int grade, int level) onPlay;

  /// Starts SayIt for the picked grade and level.
  final void Function(int grade, int level) onSayIt;
  final VoidCallback onOpenParent;

  static const playableGrades = {1, 2, 3};
  static const levels = 5;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _grade = 1;
  int? _level;

  /// Highest unlocked level of [g] unless the child picked another.
  int _levelFor(int g) {
    final picked = _level;
    if (picked != null && widget.store.isUnlocked(g, picked)) return picked;
    var best = 1;
    for (var l = 1; l <= HomeScreen.levels; l++) {
      if (widget.store.isUnlocked(g, l)) best = l;
    }
    return best;
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final store = widget.store;
    final level = _levelFor(_grade);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(child: Text('Tin Tin English', style: t.titleLarge)),
                SizedBox(
                  key: const ValueKey('parent-button'),
                  width: AppTheme.minTarget,
                  height: AppTheme.minTarget,
                  child: IconButton(
                    onPressed: widget.onOpenParent,
                    tooltip: 'Dành cho bố mẹ',
                    icon: const Icon(Icons.settings, size: 32),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: LayoutBuilder(
                      builder: (context, box) => Center(
                        child: TinTin(
                          state: TinTinState.idle,
                          size: box.maxHeight.clamp(80.0, 200.0),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 5,
                    // Scrolls on short screens (landscape phones) instead of
                    // overflowing; centred when there is room.
                    child: LayoutBuilder(
                      builder: (context, box) => SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: box.maxHeight),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text('Em học lớp mấy?', style: t.bodyLarge),
                              const SizedBox(height: 8),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  for (var g = 1; g <= 5; g++) _gradeTile(g, t),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Text('Chọn cấp độ', style: t.bodyLarge),
                              const SizedBox(height: 8),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 12,
                                runSpacing: 12,
                                children: [
                                  for (var l = 1; l <= HomeScreen.levels; l++)
                                    _levelTile(l, level, t),
                                ],
                              ),
                              const SizedBox(height: 24),
                              FilledButton.icon(
                                key: const ValueKey('play'),
                                onPressed: () => widget.onPlay(_grade, level),
                                icon: const Icon(Icons.play_arrow, size: 36),
                                label: const Text('Chơi'),
                              ),
                              if (widget.sayItAvailability ==
                                      SpeechAvailability.available &&
                                  store.sayItEnabled) ...[
                                const SizedBox(height: 12),
                                _sayItEntry(t, level),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gradeTile(int g, TextTheme t) {
    final playable = HomeScreen.playableGrades.contains(g);
    final selected = g == _grade;
    return Semantics(
      button: true,
      enabled: playable,
      selected: selected,
      label: playable ? 'Lớp $g' : 'Lớp $g, sắp có',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('grade-$g'),
        onTap: playable
            ? () => setState(() {
                _grade = g;
                _level = null;
              })
            : null,
        child: Container(
          constraints: const BoxConstraints(minWidth: 120, minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Lớp $g',
                style: t.bodyLarge!.copyWith(
                  color: selected
                      ? AppTheme.background
                      : (playable ? AppTheme.text : AppTheme.muted),
                ),
              ),
              if (!playable)
                Text('Sắp có', style: t.bodyMedium!.copyWith(fontSize: 28)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _levelTile(int l, int current, TextTheme t) {
    final store = widget.store;
    final unlocked = store.isUnlocked(_grade, l);
    final stars = store.starsFor(_grade, l);
    final selected = unlocked && l == current;
    return Semantics(
      button: true,
      enabled: unlocked,
      selected: selected,
      label: unlocked ? 'Cấp $l, $stars sao' : 'Cấp $l, chưa mở khóa',
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('level-$l'),
        onTap: unlocked ? () => setState(() => _level = l) : null,
        child: Container(
          width: 96,
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: selected ? AppTheme.accent : AppTheme.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$l',
                style: t.titleLarge!.copyWith(
                  color: selected ? AppTheme.background : AppTheme.text,
                ),
              ),
              if (unlocked)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < 3; i++)
                      Icon(
                        i < stars ? Icons.star : Icons.star_border,
                        size: 22,
                        color: i < stars
                            ? AppTheme.yellow
                            : (selected ? AppTheme.background : AppTheme.muted),
                      ),
                  ],
                )
              else
                const Icon(Icons.lock, size: 26, color: AppTheme.muted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sayItEntry(TextTheme t, int level) {
    // A real button, so TalkBack can focus and activate it.
    return FilledButton.tonalIcon(
      key: const ValueKey('sayit-entry'),
      onPressed: () => widget.onSayIt(_grade, level),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, AppTheme.minTarget),
        backgroundColor: AppTheme.surface,
        foregroundColor: AppTheme.text,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        side: const BorderSide(color: AppTheme.accent, width: 3),
      ),
      icon: const Icon(Icons.mic, color: AppTheme.accent, size: 32),
      label: Text('Luyện nói', style: t.bodyLarge),
    );
  }
}
