import 'content_repository.dart';
import 'models.dart';

class CurriculumPosition {
  const CurriculumPosition({
    required this.grade,
    required this.currentUnitIndex,
  });
  final int grade, currentUnitIndex;
}

enum UnitWindow { current, currentPlus1, currentPlus2, allLearned }

/// Units in [w] relative to the learner's position (unit indices, clamped at
/// the first unit; never includes units after the current one).
List<Unit> unitsForLevel(
  ContentRepository r,
  CurriculumPosition p,
  UnitWindow w,
) {
  final back = switch (w) {
    UnitWindow.current => 0,
    UnitWindow.currentPlus1 => 1,
    UnitWindow.currentPlus2 => 2,
    UnitWindow.allLearned => p.currentUnitIndex,
  };
  final lo = p.currentUnitIndex - back;
  return r
      .unitsFor(p.grade)
      .where((u) => u.index >= lo && u.index <= p.currentUnitIndex)
      .toList();
}
