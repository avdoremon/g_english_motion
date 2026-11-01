import '../content/models.dart';
import 'level_config.dart';

class Scoring {
  const Scoring._();

  static int points(int correct) => correct * 100;

  static int stars(int correct, int total) {
    if (total == 0) return 0;
    final c = correct * 100;
    if (c >= 90 * total) return 3;
    if (c >= 75 * total) return 2;
    if (c >= 50 * total) return 1;
    return 0;
  }

  static int sayItStars(int correctOfNine) {
    RangeError.checkValueInInterval(correctOfNine, 0, 9, 'correctOfNine');
    if (correctOfNine >= 8) return 3;
    if (correctOfNine >= 7) return 2;
    if (correctOfNine >= 5) return 1;
    return 0;
  }

  static bool unlocksNext(int stars) => stars >= 1;

  static Duration timeFor(LevelConfig c, ModeKind m, {int slots = 0}) {
    final base = c.baseTime.inMilliseconds;
    final ms = switch (m) {
      ModeKind.laneJump || ModeKind.sayIt => base,
      ModeKind.skyShoot => base * 3 ~/ 2,
      ModeKind.dragSpell => base + 3000 * slots,
    };
    return Duration(milliseconds: ms);
  }
}
