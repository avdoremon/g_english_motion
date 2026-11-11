import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../content/history_store.dart';
import '../input/confirm_gesture.dart';

/// Local persistence (progress, parent settings, question history) on
/// SharedPreferences.
///
/// Stored keys:
/// - `progress.stars.g{grade}.l{level}`  int 0..3
/// - `progress.unit.g{grade}`            int >= 1
/// - `progress.confirmGesture`           string (ConfirmGesture.name)
/// - `progress.sayIt`                    bool
/// - `progress.puppySays`                bool
/// - `progress.safetyAck`                bool
/// - `progress.playMs`                   int (play time towards a break)
/// - `progress.playAt`                   int (ms since epoch, last update)
/// - `history.recent`                    string list, oldest -> newest
/// - `history.wrong`                     string list (set)
///
/// All state is cached in memory: every mutator updates the cache
/// synchronously (so reads and the "stars only rise" rule are never stale,
/// even when callers do not await) and then queues an awaited write of the
/// resulting value. Queued writes run strictly in call order.
///
/// Must be a single app-wide instance: two instances over the same
/// SharedPreferences would clobber each other's lists. If a write fails the
/// caller sees the error and the cache stays ahead of disk until restart;
/// later writes still proceed.
/// Corrupted stored values fall back to defaults.
class ProgressStore implements HistoryStore {
  static const maxRecent = InMemoryHistoryStore.maxRecent;

  /// Wrong ids are capped too: the set only ever grows otherwise, and a list
  /// that grows without bound is written to disk on every wrong answer.
  /// Oldest marked first out (the set keeps insertion order).
  static const maxWrong = maxRecent;

  static const _recentKey = 'history.recent';
  static const _wrongKey = 'history.wrong';
  static const _gestureKey = 'progress.confirmGesture';
  static const _sayItKey = 'progress.sayIt';
  static const _puppySaysKey = 'progress.puppySays';
  static const _safetyKey = 'progress.safetyAck';
  static const _playMsKey = 'progress.playMs';
  static const _playAtKey = 'progress.playAt';

  /// A gap without play this long counts as a real break: the play time
  /// banked towards the next "take a break" reminder starts from zero.
  static const breakGap = Duration(minutes: 10);

  static String _starsKey(int g, int l) => 'progress.stars.g$g.l$l';
  static String _unitKey(int g) => 'progress.unit.g$g';

  final SharedPreferences _p;
  final List<String> _recent;
  final Set<String> _wrong;

  /// Values written since construction (newest wins over [_p]).
  final Map<String, Object> _cache = {};
  Future<void> _tail = Future.value();

  ProgressStore(SharedPreferences p)
    : _p = p,
      _recent = _dedupeKeepLast(_readList(p, _recentKey)),
      _wrong = _readList(p, _wrongKey).toSet() {
    if (_recent.length > maxRecent) {
      _recent.removeRange(0, _recent.length - maxRecent);
    }
    if (_capWrong()) {
      // Persist the trim, so an over-long stored list does not linger on
      // disk until the next markWrong / clearWrong.
      unawaited(_set(_wrongKey, _wrong.toList()).catchError((Object _) {}));
    }
  }

  /// Drops the oldest entries beyond [maxWrong]; true if any were dropped.
  bool _capWrong() {
    var dropped = false;
    while (_wrong.length > maxWrong) {
      _wrong.remove(_wrong.first);
      dropped = true;
    }
    return dropped;
  }

  static List<String> _readList(SharedPreferences p, String key) {
    final v = p.get(key);
    return v is List ? v.whereType<String>().toList() : <String>[];
  }

  /// Removes duplicates keeping the LAST occurrence (like re-asking an id).
  static List<String> _dedupeKeepLast(List<String> ids) {
    final seen = <String>{};
    return ids.reversed.where(seen.add).toList().reversed.toList();
  }

  Object? _get(String key) => _cache[key] ?? _p.get(key);

  /// Runs [write] after all previously queued writes (even failed ones).
  Future<void> _enqueue(Future<void> Function() write) {
    final next = _tail.catchError((_) {}).then((_) => write());
    _tail = next;
    return next;
  }

  /// Updates the cache synchronously, then queues the persistent write.
  Future<void> _set(String key, Object value) {
    _cache[key] = value;
    return _enqueue(() async {
      if (value is int) {
        await _p.setInt(key, value);
      } else if (value is bool) {
        await _p.setBool(key, value);
      } else if (value is String) {
        await _p.setString(key, value);
      } else if (value is List<String>) {
        await _p.setStringList(key, value);
      }
    });
  }

  // ---- stars / unlocking ----

  int starsFor(int grade, int level) {
    final v = _get(_starsKey(grade, level));
    return v is int ? v.clamp(0, 3) : 0;
  }

  Future<void> saveStars(int grade, int level, int stars) {
    if (level < 1) return Future.value();
    final s = stars.clamp(0, 3);
    if (s <= starsFor(grade, level)) return Future.value();
    return _set(_starsKey(grade, level), s);
  }

  bool isUnlocked(int grade, int level) =>
      level == 1 || (level > 1 && starsFor(grade, level - 1) >= 1);

  // ---- current unit ----

  int currentUnit(int grade) {
    final v = _get(_unitKey(grade));
    return v is int && v >= 1 ? v : 1;
  }

  Future<void> setCurrentUnit(int grade, int unitIndex) =>
      _set(_unitKey(grade), unitIndex < 1 ? 1 : unitIndex);

  // ---- parent settings ----

  ConfirmGesture get confirmGesture {
    final v = _get(_gestureKey);
    for (final g in ConfirmGesture.values) {
      if (g.name == v) return g;
    }
    return ConfirmGesture.jump;
  }

  Future<void> setConfirmGesture(ConfirmGesture g) => _set(_gestureKey, g.name);

  /// Whether the parent allows SayIt (the microphone mode).
  ///
  /// Off until a parent switches it on: that switch is the ONLY place the
  /// microphone is ever requested, so a default of "on" meant a fresh
  /// install showed the parent a switch that was already on while the Home
  /// entry stayed hidden (the OS was never asked) and the only way out was
  /// toggling it off and on again.
  bool get sayItEnabled {
    final v = _get(_sayItKey);
    return v is bool ? v : false;
  }

  Future<void> setSayItEnabled(bool v) => _set(_sayItKey, v);

  /// Parent switch for the puppySays mode (default off).
  bool get puppySaysEnabled {
    final v = _get(_puppySaysKey);
    return v is bool ? v : false;
  }

  Future<void> setPuppySaysEnabled(bool v) => _set(_puppySaysKey, v);

  // ---- play time towards the break reminder ----
  //
  // Kept in the store, not in the shell: the shell is built per play flow, so
  // going Home between two short levels would otherwise restart the
  // 20-minute clock and the child would never be reminded.

  /// Play time banked towards the next break reminder. A gap of at least
  /// [breakGap] since the last update (or a clock that went backwards) counts
  /// as a real break and starts from zero.
  Duration playedTowardsBreak({DateTime? now}) {
    final ms = _get(_playMsKey);
    final at = _get(_playAtKey);
    if (ms is! int || at is! int || ms <= 0) return Duration.zero;
    final gap = (now ?? DateTime.now()).millisecondsSinceEpoch - at;
    if (gap < 0 || gap >= breakGap.inMilliseconds) return Duration.zero;
    return Duration(milliseconds: ms);
  }

  /// Adds [d] of play time to the count (and marks it as "played just now").
  Future<void> addPlayTime(Duration d, {DateTime? now}) {
    final t = now ?? DateTime.now();
    final banked =
        playedTowardsBreak(now: t) + (d < Duration.zero ? Duration.zero : d);
    _set(_playMsKey, banked.inMilliseconds);
    return _set(_playAtKey, t.millisecondsSinceEpoch);
  }

  /// Starts the count over (the reminder was just shown).
  Future<void> resetPlayTime({DateTime? now}) {
    _set(_playMsKey, 0);
    return _set(_playAtKey, (now ?? DateTime.now()).millisecondsSinceEpoch);
  }

  bool get safetyAcknowledged {
    final v = _get(_safetyKey);
    return v is bool ? v : false;
  }

  Future<void> acknowledgeSafety() => _set(_safetyKey, true);

  // ---- HistoryStore ----

  @override
  List<String> recentIds() => List.unmodifiable(_recent);

  @override
  Set<String> wrongIds() => Set.unmodifiable(_wrong);

  @override
  Future<void> recordAsked(List<String> ids) {
    for (final id in ids) {
      _recent.remove(id);
      _recent.add(id);
    }
    if (_recent.length > maxRecent) {
      _recent.removeRange(0, _recent.length - maxRecent);
    }
    return _set(_recentKey, List<String>.of(_recent));
  }

  @override
  Future<void> markWrong(String id) {
    _wrong.add(id);
    _capWrong();
    return _set(_wrongKey, _wrong.toList());
  }

  @override
  Future<void> clearWrong(String id) {
    _wrong.remove(id);
    return _set(_wrongKey, _wrong.toList());
  }
}
