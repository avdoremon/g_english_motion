import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:g_english_motion/input/pose_frame_source.dart';
import 'package:g_english_motion/progress/progress_store.dart';

Future<(SharedPreferences, ProgressStore)> make([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final p = await SharedPreferences.getInstance();
  return (p, ProgressStore(p));
}

void main() {
  test('level 1 unlocked, level 2 locked', () async {
    final (_, s) = await make();
    expect(s.isUnlocked(1, 1), isTrue);
    expect(s.isUnlocked(1, 2), isFalse);
  });

  test('saveStars(1,1,1) unlocks level 2', () async {
    final (_, s) = await make();
    await s.saveStars(1, 1, 1);
    expect(s.starsFor(1, 1), 1);
    expect(s.isUnlocked(1, 2), isTrue);
    expect(s.isUnlocked(1, 3), isFalse);
    expect(s.isUnlocked(2, 2), isFalse);
  });

  test('saveStars never lowers, clamps, ignores invalid level', () async {
    final (_, s) = await make();
    await s.saveStars(1, 1, 3);
    await s.saveStars(1, 1, 1);
    expect(s.starsFor(1, 1), 3);
    await s.saveStars(1, 2, 9);
    expect(s.starsFor(1, 2), 3);
    await s.saveStars(1, 0, 2);
    expect(s.starsFor(1, 0), 0);
  });

  test('defaults', () async {
    final (_, s) = await make();
    expect(s.currentUnit(1), 1);
    expect(s.confirmGesture, ConfirmGesture.jump);
    expect(s.sayItEnabled, isTrue);
    expect(s.safetyAcknowledged, isFalse);
  });

  test('setCurrentUnit min 1', () async {
    final (_, s) = await make();
    await s.setCurrentUnit(1, 4);
    expect(s.currentUnit(1), 4);
    await s.setCurrentUnit(1, 0);
    expect(s.currentUnit(1), 1);
  });

  test('recentIds keeps 200 newest when 250 recorded', () async {
    final (_, s) = await make();
    await s.recordAsked([for (var i = 0; i < 250; i++) 'id$i']);
    final r = s.recentIds();
    expect(r.length, 200);
    expect(r.first, 'id50');
    expect(r.last, 'id249');
  });

  test('re-asked ids move to the end', () async {
    final (_, s) = await make();
    await s.recordAsked(['a', 'b', 'c']);
    await s.recordAsked(['a']);
    expect(s.recentIds(), ['b', 'c', 'a']);
  });

  test('markWrong then clearWrong -> empty', () async {
    final (_, s) = await make();
    await s.markWrong('x');
    expect(s.wrongIds(), {'x'});
    await s.clearWrong('x');
    expect(s.wrongIds(), isEmpty);
  });

  test('settings mutate and persist across instances', () async {
    final (p, s) = await make();
    await s.saveStars(2, 1, 2);
    await s.setCurrentUnit(2, 3);
    await s.setConfirmGesture(ConfirmGesture.raiseHands);
    await s.setSayItEnabled(false);
    await s.acknowledgeSafety();
    await s.recordAsked(['a', 'b']);
    await s.markWrong('w');
    final s2 = ProgressStore(p);
    expect(s2.starsFor(2, 1), 2);
    expect(s2.currentUnit(2), 3);
    expect(s2.confirmGesture, ConfirmGesture.raiseHands);
    expect(s2.sayItEnabled, isFalse);
    expect(s2.safetyAcknowledged, isTrue);
    expect(s2.recentIds(), ['a', 'b']);
    expect(s2.wrongIds(), {'w'});
  });

  test('concurrent markWrong/clearWrong lose no updates', () async {
    final (p, s) = await make();
    final futures = <Future<void>>[
      s.markWrong('a'),
      s.markWrong('b'),
      s.markWrong('c'),
      s.clearWrong('b'),
      s.markWrong('d'),
      s.recordAsked(['r1']),
      s.recordAsked(['r2']),
    ];
    await Future.wait(futures);
    expect(s.wrongIds(), {'a', 'c', 'd'});
    expect(s.recentIds(), ['r1', 'r2']);
    final s2 = ProgressStore(p);
    expect(s2.wrongIds(), {'a', 'c', 'd'});
    expect(s2.recentIds(), ['r1', 'r2']);
  });

  test('corrupted values fall back to defaults', () async {
    final (_, s) = await make({
      'progress.stars.g1.l1': 'abc',
      'progress.stars.g1.l2': -5,
      'progress.unit.g1': 'zzz',
      'progress.confirmGesture': 42,
      'progress.sayIt': 'yes',
      'progress.safetyAck': 7,
      'history.recent': 'notalist',
      'history.wrong': 12,
    });
    expect(s.starsFor(1, 1), 0);
    expect(s.starsFor(1, 2), 0);
    expect(s.isUnlocked(1, 2), isFalse);
    expect(s.currentUnit(1), 1);
    expect(s.confirmGesture, ConfirmGesture.jump);
    expect(s.sayItEnabled, isTrue);
    expect(s.safetyAcknowledged, isFalse);
    expect(s.recentIds(), isEmpty);
    expect(s.wrongIds(), isEmpty);
    await s.markWrong('ok');
    expect(s.wrongIds(), {'ok'});
  });
}
