import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/content_repository.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/content/models.dart';

void main() {
  final repo = ContentRepository([
    for (var i = 1; i <= 4; i++)
      Unit(grade: 1, index: i, id: 'u0$i', title: 'U$i', items: const []),
    const Unit(grade: 2, index: 1, id: 'u01', title: 'G2', items: []),
  ]);
  List<String> ids(int cur, UnitWindow w, {int grade = 1}) => unitsForLevel(
    repo,
    CurriculumPosition(grade: grade, currentUnitIndex: cur),
    w,
  ).map((u) => u.id).toList();

  test('current', () => expect(ids(3, UnitWindow.current), ['u03']));
  test(
    'currentPlus1',
    () => expect(ids(3, UnitWindow.currentPlus1), ['u02', 'u03']),
  );
  test(
    'currentPlus2',
    () => expect(ids(3, UnitWindow.currentPlus2), ['u01', 'u02', 'u03']),
  );
  test(
    'currentPlus2 clamps at unit 1',
    () => expect(ids(1, UnitWindow.currentPlus2), ['u01']),
  );
  test(
    'allLearned',
    () => expect(ids(3, UnitWindow.allLearned), ['u01', 'u02', 'u03']),
  );
  test(
    'other grade not mixed in',
    () => expect(ids(1, UnitWindow.allLearned, grade: 2), ['u01']),
  );
}
