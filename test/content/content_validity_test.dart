import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g_english_motion/content/content_repository.dart';
import 'package:g_english_motion/content/curriculum.dart';
import 'package:g_english_motion/content/history_store.dart';
import 'package:g_english_motion/content/models.dart';
import 'package:g_english_motion/content/question_generator.dart';
import 'package:g_english_motion/levels/level_config.dart';

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
        expect(
          it.sentencePatterns.any(
            (s) => RegExp(
              '(^|\\s)${RegExp.escape(it.word)}(\\s|\$)',
              caseSensitive: false,
            ).hasMatch(s),
          ),
          isTrue,
          reason: '${it.id}: skyShoot needs a sentence containing the word',
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
            anyOf(ModeKind.laneJump, ModeKind.sayIt),
            reason: '${it.id}: grades 1-2 only use laneJump/sayIt',
          );
        }
        if (it.modes.contains(ModeKind.sayIt)) {
          expect(it.syllables, lessThanOrEqualTo(2), reason: it.id);
        }
      }
      for (final v in it.spokenVariants) {
        expect(v, v.toLowerCase(), reason: '${it.id} variant "$v"');
        expect(
          RegExp(r"^[a-z0-9 ]+$").hasMatch(v),
          isTrue,
          reason: '${it.id} variant "$v" has punctuation',
        );
        expect(v, isNot(it.word), reason: it.id);
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
  });
}
