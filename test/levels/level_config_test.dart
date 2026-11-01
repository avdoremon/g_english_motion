import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/levels/level_config.dart';

import '../helpers/map_asset_bundle.dart';

void main() {
  final json = File('assets/config/levels.json').readAsStringSync();
  late List<LevelConfig> levels;
  setUp(() async {
    levels = await LevelConfig.load(
      MapAssetBundle({'assets/config/levels.json': json}),
    );
  });

  test('five levels with Global Constraints values', () {
    expect(levels.map((l) => l.level), [1, 2, 3, 4, 5]);
    expect(levels.map((l) => l.questionCount), [8, 10, 10, 12, 12]);
    expect(levels.map((l) => l.baseTime.inSeconds), [20, 18, 15, 12, 10]);
    expect(levels.map((l) => l.choiceCount), [3, 3, 4, 4, 4]);
    expect(levels.map((l) => l.hints), [
      HintMode.full,
      HintMode.full,
      HintMode.partial,
      HintMode.none,
      HintMode.none,
    ]);
    expect(levels.map((l) => l.window), [
      UnitWindow.current,
      UnitWindow.currentPlus1,
      UnitWindow.currentPlus2,
      UnitWindow.allLearned,
      UnitWindow.allLearned,
    ]);
  });

  test('level 1 and 5 spot check', () {
    expect(levels.first.questionCount, 8);
    expect(levels.first.baseTime, const Duration(seconds: 20));
    expect(levels.last.questionCount, 12);
    expect(levels.last.baseTime, const Duration(seconds: 10));
  });

  test('bad json names the file', () {
    expect(
      LevelConfig.load(
        MapAssetBundle({'assets/config/levels.json': '[{"level":1}]'}),
      ),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          contains('levels.json'),
        ),
      ),
    );
  });
}
