import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'package:g_english_motion/input/pose_frame_source.dart';
import 'package:g_english_motion/progress/progress_store.dart';

Future<(SharedPreferences, ProgressStore)> make([
  Map<String, Object> initial = const {},
]) async {
  SharedPreferences.setMockInitialValues(initial);
  final p = await SharedPreferences.getInstance();
  return (p, ProgressStore(p));
}

/// Store whose first write to [slowKey] completes late; writes to
/// [failKey] throw once.
class FakeStore extends InMemorySharedPreferencesStore {
  FakeStore({this.slowKey, this.failKey}) : super.empty();
  final String? slowKey;
  final String? failKey;
  bool _slowUsed = false;
  bool _failUsed = false;

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    if (key == 'flutter.$failKey' && !_failUsed) {
      _failUsed = true;
      throw StateError('disk full');
    }
    if (key == 'flutter.$slowKey' && !_slowUsed) {
      _slowUsed = true;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return super.setValue(valueType, key, value);
  }
}

Future<(SharedPreferences, FakeStore)> makeFake(FakeStore store) async {
  SharedPreferences.resetStatic();
  SharedPreferencesStorePlatform.instance = store;
  return (await SharedPreferences.getInstance(), store);
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

  test('un-awaited saveStars 3 then 1 keeps 3 (cache and disk)', () async {
    final (p, s) = await make();
    final f1 = s.saveStars(1, 1, 3);
    final f2 = s.saveStars(1, 1, 1);
    expect(s.starsFor(1, 1), 3);
    expect(s.isUnlocked(1, 2), isTrue);
    await Future.wait([f1, f2]);
    expect(s.starsFor(1, 1), 3);
    expect(p.getInt('progress.stars.g1.l1'), 3);
  });

  test('un-awaited setters are reflected immediately', () async {
    final (_, s) = await make();
    final fs = [
      s.setCurrentUnit(1, 5),
      s.setConfirmGesture(ConfirmGesture.raiseHands),
      s.setSayItEnabled(false),
      s.acknowledgeSafety(),
    ];
    expect(s.currentUnit(1), 5);
    expect(s.confirmGesture, ConfirmGesture.raiseHands);
    expect(s.sayItEnabled, isFalse);
    expect(s.safetyAcknowledged, isTrue);
    await Future.wait(fs);
  });

  test('unknown gesture name or non-string falls back to jump', () async {
    final (_, s) = await make({'progress.confirmGesture': 'wave'});
    expect(s.confirmGesture, ConfirmGesture.jump);
    final (_, s2) = await make({'progress.confirmGesture': 3});
    expect(s2.confirmGesture, ConfirmGesture.jump);
  });

  test('stored recent list is de-duped keeping the last occurrence', () async {
    final (_, s) = await make({
      'history.recent': ['a', 'b', 'a', 'c'],
    });
    expect(s.recentIds(), ['b', 'a', 'c']);
  });

  test('writes to the same key are serialized (slow first write)', () async {
    final (p, store) = await makeFake(FakeStore(slowKey: 'history.wrong'));
    final s = ProgressStore(p);
    final f1 = s.markWrong('a');
    final f2 = s.markWrong('b');
    await Future.wait([f1, f2]);
    // Without serialization the slow first write (['a']) would land last on
    // the underlying store.
    final disk = (await store.getAll())['flutter.history.wrong'];
    expect(disk, unorderedEquals(['a', 'b']));
  });

  test('failed write surfaces error; later writes still proceed', () async {
    final (p, _) = await makeFake(FakeStore(failKey: 'history.wrong'));
    final s = ProgressStore(p);
    await expectLater(s.markWrong('a'), throwsStateError);
    await s.markWrong('b');
    expect(p.getStringList('history.wrong'), unorderedEquals(['a', 'b']));
  });
}
