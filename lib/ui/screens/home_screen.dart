import 'package:flutter/material.dart';

import '../../progress/progress_store.dart';
import '../../speech/speech_source.dart';
import '../kit/kit.dart';
import '../mascot/tin_tin.dart';
import '../theme/app_theme.dart';

/// Home: grade picker, level picker (stars + lock) and the Play button.
///
/// All five grades have content; a grade without content would be shown disabled
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

  static const playableGrades = {1, 2, 3, 4, 5};
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
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text.rich(
                        TextSpan(
                          children: [
                            const TextSpan(text: 'Tin Tin '),
                            TextSpan(
                              text: 'English',
                              style: TextStyle(color: AppTheme.yellow),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        style: AppTheme.textStyles.heading,
                      ),
                    ),
                  ),
                ),
                RoundIconButton(
                  key: const ValueKey('parent-button'),
                  icon: Icons.tune,
                  semanticLabel: 'Dành cho bố mẹ',
                  onPressed: widget.onOpenParent,
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
                          state: TinTinState.cheer,
                          size: box.maxHeight.clamp(80.0, 250.0),
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
                              StickerCard(
                                fill: AppTheme.surface,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text('Em học lớp mấy?', style: t.bodyLarge),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        for (var g = 1; g <= 5; g++)
                                          _gradeTile(g, t),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Text('Chọn cấp độ', style: t.bodyLarge),
                                    const SizedBox(height: 8),
                                    Wrap(
                                      alignment: WrapAlignment.center,
                                      spacing: 10,
                                      runSpacing: 10,
                                      children: [
                                        for (
                                          var l = 1;
                                          l <= HomeScreen.levels;
                                          l++
                                        )
                                          _levelTile(l, level, t),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 20),
                              Wrap(
                                alignment: WrapAlignment.center,
                                spacing: 16,
                                runSpacing: 14,
                                children: [
                                  BigButton(
                                    key: const ValueKey('play'),
                                    label: 'Chơi',
                                    icon: Icons.play_arrow,
                                    onPressed: () =>
                                        widget.onPlay(_grade, level),
                                  ),
                                  if (widget.sayItAvailability ==
                                          SpeechAvailability.available &&
                                      store.sayItEnabled)
                                    // A real button, so TalkBack can focus
                                    // and activate it.
                                    BigButton(
                                      key: const ValueKey('sayit-entry'),
                                      label: 'Luyện nói',
                                      icon: Icons.mic,
                                      color: AppTheme.accent,
                                      onPressed: () =>
                                          widget.onSayIt(_grade, level),
                                    ),
                                ],
                              ),
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
    void pick() => setState(() {
      _grade = g;
      _level = null;
    });
    // onTap on the Semantics itself: excludeSemantics drops the child's own
    // tap action, so without it TalkBack would announce a button whose
    // double-tap does nothing.
    return Semantics(
      button: true,
      enabled: playable,
      selected: selected,
      label: playable ? 'Lớp $g' : 'Lớp $g, sắp có',
      onTap: playable ? pick : null,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('grade-$g'),
        onTap: playable ? pick : null,
        child: Container(
          constraints: const BoxConstraints(minWidth: 84, minHeight: 72),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: _tileDecoration(selected),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  'Lớp $g',
                  maxLines: 1,
                  style: t.bodyLarge!.copyWith(
                    fontWeight: FontWeight.w700,
                    color: selected
                        ? AppTheme.ink
                        : (playable ? AppTheme.text : AppTheme.muted),
                  ),
                ),
              ),
              if (!playable)
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    'Sắp có',
                    maxLines: 1,
                    style: AppTheme.textStyles.play.copyWith(
                      color: AppTheme.muted,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Selected tiles are the yellow "pressed up" chip with an ink ring.
  BoxDecoration _tileDecoration(bool selected) => BoxDecoration(
    color: selected ? AppTheme.yellow : AppTheme.surfaceLight,
    borderRadius: BorderRadius.circular(20),
    border: selected ? Border.all(color: AppTheme.ink, width: 4) : null,
    boxShadow: selected
        ? const [BoxShadow(color: AppTheme.ink, offset: Offset(0, 5))]
        : null,
  );

  Widget _levelTile(int l, int current, TextTheme t) {
    final store = widget.store;
    final unlocked = store.isUnlocked(_grade, l);
    final stars = store.starsFor(_grade, l);
    final selected = unlocked && l == current;
    void pick() => setState(() => _level = l);
    // See _gradeTile: the announced button must really act on a tap.
    return Semantics(
      button: true,
      enabled: unlocked,
      selected: selected,
      label: unlocked ? 'Cấp $l, $stars sao' : 'Cấp $l, chưa mở khóa',
      onTap: unlocked ? pick : null,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('level-$l'),
        onTap: unlocked ? pick : null,
        child: Container(
          width: 84,
          constraints: const BoxConstraints(minHeight: 72),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: _tileDecoration(selected),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$l',
                maxLines: 1,
                style: AppTheme.textStyles.heading.copyWith(
                  color: selected ? AppTheme.ink : AppTheme.text,
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
                            : (selected ? AppTheme.ink : AppTheme.muted),
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
}
