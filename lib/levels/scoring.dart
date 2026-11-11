import '../content/models.dart';
import 'level_config.dart';

class Scoring {
  const Scoring._();

  /// 100 points per correct answer; a negative count scores 0.
  static int points(int correct) => (correct < 0 ? 0 : correct) * 100;

  /// 3 stars from 90 %, 2 from 75 %, 1 from 50 % (integer arithmetic, no
  /// rounding). Out-of-range input is clamped rather than thrown on (a
  /// scoring slip must never crash the result screen): [correct] is limited
  /// to 0..[total], and a [total] of 0 or less grades nothing (0 stars).
  static int stars(int correct, int total) {
    if (total <= 0) return 0;
    final c = correct.clamp(0, total) * 100;
    if (c >= 90 * total) return 3;
    if (c >= 75 * total) return 2;
    if (c >= 50 * total) return 1;
    return 0;
  }

  /// 3 stars from 8 of 9 words, 2 from 7, 1 from 5. Out-of-range input is
  /// clamped to 0..9 rather than thrown on, like [stars].
  static int sayItStars(int correctOfNine) {
    final c = correctOfNine.clamp(0, 9);
    if (c >= 8) return 3;
    if (c >= 7) return 2;
    if (c >= 5) return 1;
    return 0;
  }

  static bool unlocksNext(int stars) => stars >= 1;

  /// Time limit for one question. [slots] (drag-spell tiles) below 0 count as
  /// 0.
  static Duration timeFor(LevelConfig c, ModeKind m, {int slots = 0}) {
    if (slots < 0) slots = 0;
    final base = c.baseTime.inMilliseconds;
    final ms = switch (m) {
      ModeKind.laneJump || ModeKind.sayIt => base,
      ModeKind.skyShoot => base * 3 ~/ 2,
      ModeKind.dragSpell => base + 3000 * slots,
      ModeKind.catchIt || ModeKind.yesNo => base,
      ModeKind.memoryFlip || ModeKind.balloonPop => base * 3 ~/ 2,
      ModeKind.puppySays => base * 2,
    };
    return Duration(milliseconds: ms);
  }
}
