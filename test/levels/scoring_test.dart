import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/levels/level_config.dart';
import 'package:g_english_motion/levels/scoring.dart';

import '../helpers/map_asset_bundle.dart';

void main() {
  final json = File('assets/config/levels.json').readAsStringSync();
  late List<LevelConfig> levels;
  setUp(() async {
    levels = await LevelConfig.load(
      MapAssetBundle({'assets/config/levels.json': json}),
    );
  });

  test('points = correct * 100', () {
    expect(Scoring.points(7), 700);
    expect(Scoring.points(0), 0);
  });

  test('stars thresholds use integers', () {
    expect(Scoring.stars(4, 8), 1);
    expect(Scoring.stars(3, 8), 0);
    expect(Scoring.stars(6, 8), 2);
    expect(Scoring.stars(9, 10), 3);
    expect(Scoring.stars(7, 10), 1);
    expect(Scoring.stars(0, 0), 0);
    expect(Scoring.stars(8, 8), 3);
  });

  test('sayItStars', () {
    expect(Scoring.sayItStars(4), 0);
    expect(Scoring.sayItStars(5), 1);
    expect(Scoring.sayItStars(6), 1);
    expect(Scoring.sayItStars(7), 2);
    expect(Scoring.sayItStars(8), 3);
    expect(Scoring.sayItStars(9), 3);
    expect(Scoring.sayItStars(0), 0);
    expect(() => Scoring.sayItStars(-1), throwsRangeError);
    expect(() => Scoring.sayItStars(10), throwsRangeError);
  });

  test('unlocksNext', () {
    expect(Scoring.unlocksNext(0), isFalse);
    expect(Scoring.unlocksNext(1), isTrue);
    expect(Scoring.unlocksNext(3), isTrue);
  });

  test('timeFor per mode', () {
    expect(
      Scoring.timeFor(levels[2], ModeKind.skyShoot),
      const Duration(milliseconds: 22500),
    );
    expect(
      Scoring.timeFor(levels[4], ModeKind.dragSpell, slots: 6),
      const Duration(seconds: 28),
    );
    expect(
      Scoring.timeFor(levels[0], ModeKind.laneJump),
      const Duration(seconds: 20),
    );
    expect(
      Scoring.timeFor(levels[0], ModeKind.sayIt),
      const Duration(seconds: 20),
    );
  });
}
