import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/speech/word_judge.dart';
import 'package:g_english_motion/content/content_repository.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/content/edit_distance.dart';
import 'package:g_english_motion/content/history_store.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_generator.dart';
import 'package:g_english_motion/levels/level_config.dart';
import 'package:g_english_motion/modes/mode_availability.dart';

/// Walks the real `assets/content/**` files (tests run from the project root).
List<MapEntry<String, Unit>> _loadUnits() {
  final files =
      Directory('assets/content')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.json'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  return [
    for (final f in files)
      MapEntry(
        f.path,
        Unit.fromJson(jsonDecode(f.readAsStringSync()) as Map<String, dynamic>),
      ),
  ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final entries = _loadUnits();
  final units = [for (final e in entries) e.value];
  final items = [
    for (final u in units)
      for (final it in u.items) (u, it),
  ];

  test('content exists for grade 1 units 1 and 2', () {
    expect(
      units.where((u) => u.grade == 1).map((u) => u.index).toSet(),
      containsAll([1, 2]),
    );
  });

  test('content exists for grade 3 units 1 and 2', () {
    expect(
      units.where((u) => u.grade == 3).map((u) => u.index).toSet(),
      containsAll([1, 2]),
    );
  });

  test('every grade 3-5 unit has dragSpell and skyShoot items', () {
    for (final u in units.where((u) => u.grade >= 3)) {
      for (final m in [ModeKind.dragSpell, ModeKind.skyShoot]) {
        expect(
          u.items.where((it) => it.modes.contains(m)),
          isNotEmpty,
          reason: 'g${u.grade} ${u.id} needs >= 1 ${m.name} item',
        );
      }
    }
  });

  test('new-mode tags are consistent with the tagging rules', () {
    final all = {for (final (_, it) in items) it.id};
    final byGrade = <int, List<ContentItem>>{};
    for (final (u, it) in items) {
      byGrade.putIfAbsent(u.grade, () => []).add(it);
    }
    for (final (u, it) in items) {
      if (it.modes.contains(ModeKind.memoryFlip) ||
          it.modes.contains(ModeKind.catchIt)) {
        expect(it.image, isNotNull, reason: '${it.id}: needs an image');
      }
      if (it.modes.contains(ModeKind.balloonPop)) {
        expect(it.image, isNotNull, reason: '${it.id}: needs an image');
        expect(
          it.distractorIds.where((d) => d != it.id && all.contains(d)).length,
          greaterThanOrEqualTo(2),
          reason: '${it.id}: balloonPop needs >= 2 usable distractors',
        );
        final near = {
          for (final o in byGrade[u.grade]!)
            if (o.word.toLowerCase() != it.word.toLowerCase() &&
                editDistance(o.word, it.word) <= 2)
              o.word.toLowerCase(),
        };
        expect(
          near.length,
          greaterThanOrEqualTo(2),
          reason: '${it.id}: balloonPop needs >= 2 near words in grade',
        );
      }
    }
  });

  test('dragSpell words and order-sentence patterns are playable', () {
    final ws = RegExp(r'\s+');
    for (final (_, it) in items.where((e) => e.$1.grade >= 3)) {
      if (it.modes.contains(ModeKind.dragSpell)) {
        expect(
          it.word.length,
          greaterThanOrEqualTo(3),
          reason: '${it.id}: dragSpell word needs >= 3 letters',
        );
        expect(
          RegExp(r'^[a-z]+$').hasMatch(it.word),
          isTrue,
          reason: '${it.id}: dragSpell word must be letters only',
        );
        for (final s in it.sentencePatterns) {
          final n = s.trim().split(ws).length;
          expect(n, inInclusiveRange(3, 6), reason: '${it.id}: "$s"');
        }
      }
      if (it.modes.contains(ModeKind.skyShoot)) {
        // Exactly once: a pattern repeating the word ("The orange is
        // orange") cannot be blanked without showing the answer, so
        // fillBlank skips it and the item needs another one.
        // Same word-boundary rule as QuestionGenerator (lookarounds, so
        // adjacent occurrences are both counted).
        final re = RegExp(
          r'(?<![\p{L}\p{N}_])' + RegExp.escape(it.word) + r'(?![\p{L}\p{N}_])',
          caseSensitive: false,
          unicode: true,
        );
        expect(
          it.sentencePatterns.any((s) => re.allMatches(s).length == 1),
          isTrue,
          reason:
              '${it.id}: skyShoot needs a sentence containing the word '
              'exactly once',
        );
      }
    }
  });

  test('ids are globally unique and distractors are valid', () {
    final ids = [for (final (_, it) in items) it.id];
    expect(ids.toSet().length, ids.length);
    final all = ids.toSet();
    for (final (u, it) in items) {
      expect(
        it.distractorIds.where((d) => d != it.id && all.contains(d)).length,
        greaterThanOrEqualTo(2),
        reason: '${it.id} needs >= 2 valid distractors',
      );
      expect(it.distractorIds, isNot(contains(it.id)), reason: it.id);
      expect(
        it.distractorIds.toSet().length,
        it.distractorIds.length,
        reason: '${it.id} duplicate distractors',
      );
      // Same-unit distractors (authoring rule for grade 1).
      final unitIds = u.items.map((e) => e.id).toSet();
      expect(unitIds.containsAll(it.distractorIds), isTrue, reason: it.id);
    }
  });

  test('images exist under assets/images and are covered by LICENSES.md', () {
    final licenses = File('assets/images/LICENSES.md').readAsStringSync();
    for (final (_, it) in items) {
      final img = it.image;
      if (img == null) continue;
      expect(
        File('assets/images/$img').existsSync(),
        isTrue,
        reason: '${it.id}: missing assets/images/$img',
      );
      final dir = img.contains('/')
          ? img.substring(0, img.lastIndexOf('/'))
          : '';
      expect(
        licenses.contains('assets/images/$dir/') || licenses.contains(img),
        isTrue,
        reason: '$img not covered by LICENSES.md',
      );
    }
  });

  test('every image is registered in the asset bundle', () async {
    for (final (_, it) in items) {
      final img = it.image;
      if (img == null) continue;
      final data = await rootBundle.load('assets/images/$img');
      expect(data.lengthInBytes, greaterThan(0), reason: img);
    }
  });

  test('item field rules', () {
    for (final (u, it) in items) {
      expect(it.syllables, greaterThanOrEqualTo(1), reason: it.id);
      expect(it.word, it.word.toLowerCase(), reason: it.id);
      expect(it.id, startsWith('g${u.grade}${u.id}-'), reason: it.id);
      if (u.grade <= 2) {
        for (final m in it.modes) {
          expect(
            m,
            anyOf(
              ModeKind.laneJump,
              ModeKind.sayIt,
              ModeKind.memoryFlip,
              ModeKind.catchIt,
              ModeKind.balloonPop,
            ),
            reason:
                '${it.id}: grades 1-2 only use laneJump/sayIt/memoryFlip/'
                'catchIt/balloonPop',
          );
        }
        if (it.modes.contains(ModeKind.sayIt)) {
          expect(it.syllables, lessThanOrEqualTo(2), reason: it.id);
        }
      }
      for (final v in it.spokenVariants) {
        // Already in the form the judge compares in, and not just the word.
        expect(WordJudge.normalize(v), v, reason: '${it.id} variant "$v"');
        expect(v, isNot(WordJudge.normalize(it.word)), reason: it.id);
      }
    }
  });

  group('QuestionGenerator can fill level plans from the real content', () {
    late List<LevelConfig> levels;
    late ContentRepository repo;
    setUpAll(() async {
      levels = await LevelConfig.load(rootBundle);
      repo = ContentRepository(units);
    });

    for (final unitIndex in [1, 2]) {
      for (final lv in [1, 5]) {
        test('grade 1 unit $unitIndex, level $lv', () {
          final level = levels.firstWhere((l) => l.level == lv);
          final plan =
              QuestionGenerator(repo, InMemoryHistoryStore(), Random(1)).plan(
                level: level,
                pos: CurriculumPosition(grade: 1, currentUnitIndex: unitIndex),
                modes: {ModeKind.laneJump},
              );
          expect(plan.length, level.questionCount);
          final pairs = plan.map(
            (q) => '${q.question.itemId}/${q.question.form}',
          );
          expect(pairs.toSet().length, pairs.length, reason: 'repeated pair');
          final pool = unitsForLevel(
            repo,
            CurriculumPosition(grade: 1, currentUnitIndex: unitIndex),
            level.window,
          );
          final itemCount = pool.fold<int>(0, (n, u) => n + u.items.length);
          // 3 laneJump forms per picturable item.
          expect(itemCount * 3, greaterThanOrEqualTo(16));
        });
      }
    }

    for (final unitIndex in [1, 2]) {
      for (final lv in [1, 5]) {
        test('grade 3 unit $unitIndex, level $lv mixes dragSpell and '
            'skyShoot', () {
          final level = levels.firstWhere((l) => l.level == lv);
          final plan =
              QuestionGenerator(repo, InMemoryHistoryStore(), Random(1)).plan(
                level: level,
                pos: CurriculumPosition(grade: 3, currentUnitIndex: unitIndex),
                modes: {ModeKind.dragSpell, ModeKind.skyShoot},
              );
          expect(plan.length, level.questionCount);
          expect(plan.map((q) => q.mode).toSet(), {
            ModeKind.dragSpell,
            ModeKind.skyShoot,
          });
        });
      }
    }

    // Sweep: every unit of every grade must be able to fill levels 1 and 5.
    for (final entry in {1: 16, 2: 16, 3: 20, 4: 20, 5: 20}.entries) {
      final modes = entry.key <= 2
          ? {ModeKind.laneJump}
          : {ModeKind.dragSpell, ModeKind.skyShoot};
      test(
        'grade ${entry.key}: all ${entry.value} units fill levels 1 and 5',
        () {
          for (var unit = 1; unit <= entry.value; unit++) {
            for (final lv in [1, 5]) {
              final level = levels.firstWhere((l) => l.level == lv);
              final plan =
                  QuestionGenerator(
                    repo,
                    InMemoryHistoryStore(),
                    Random(unit),
                  ).plan(
                    level: level,
                    pos: CurriculumPosition(
                      grade: entry.key,
                      currentUnitIndex: unit,
                    ),
                    modes: modes,
                  );
              expect(
                plan.length,
                level.questionCount,
                reason: 'grade ${entry.key} unit $unit level $lv',
              );
            }
          }
        },
      );
    }

    // Every grade, unit and level fills exactly questionCount questions for
    // each mode valid at that grade (the generator widens the content window
    // when the level's window has no item for the mode).
    for (var grade = 1; grade <= 5; grade++) {
      test('grade $grade: every unit and level 1-5 fills each valid mode', () {
        final unitCount = repo.unitsFor(grade).length;
        for (final mode in modesForGrade(grade)) {
          if (mode == ModeKind.sayIt) continue; // not question-driven
          for (var unit = 1; unit <= unitCount; unit++) {
            for (final level in levels) {
              final plan =
                  QuestionGenerator(
                    repo,
                    InMemoryHistoryStore(),
                    Random(unit),
                  ).plan(
                    level: level,
                    pos: CurriculumPosition(
                      grade: grade,
                      currentUnitIndex: unit,
                    ),
                    modes: {mode},
                  );
              expect(
                plan.length,
                level.questionCount,
                reason:
                    '${mode.name} grade $grade unit $unit '
                    'level ${level.level}',
              );
              expect(plan.every((q) => q.mode == mode), isTrue);
            }
          }
        }
      });
    }

    // A single tagged item must not carry a whole plan: the same picture
    // asked 3+ times in a row of 8 reads as a bug to a child.
    for (var grade = 1; grade <= 5; grade++) {
      test('grade $grade: new modes never ask one item more than twice', () {
        final unitCount = repo.unitsFor(grade).length;
        for (final mode in [
          ModeKind.balloonPop,
          ModeKind.memoryFlip,
          ModeKind.catchIt,
        ]) {
          if (!modesForGrade(grade).contains(mode)) continue;
          final gradeItems = {
            for (final u in repo.unitsFor(grade))
              for (final it in u.items)
                if (it.modes.contains(mode)) it.id,
          };
          if (gradeItems.length < 3) continue;
          for (var unit = 1; unit <= unitCount; unit++) {
            for (final level in levels) {
              final plan =
                  QuestionGenerator(
                    repo,
                    InMemoryHistoryStore(),
                    Random(unit),
                  ).plan(
                    level: level,
                    pos: CurriculumPosition(
                      grade: grade,
                      currentUnitIndex: unit,
                    ),
                    modes: {mode},
                  );
              final counts = <String, int>{};
              for (final q in plan) {
                counts.update(
                  q.question.itemId,
                  (c) => c + 1,
                  ifAbsent: () => 1,
                );
              }
              final worst = counts.values.fold<int>(0, math.max);
              expect(
                worst,
                lessThanOrEqualTo(2),
                reason:
                    '${mode.name} grade $grade unit $unit '
                    'level ${level.level}: $counts',
              );
            }
          }
        }
      });
    }
  });
}
