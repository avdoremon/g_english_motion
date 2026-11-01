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
/// - `progress.safetyAck`                bool
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

  static const _recentKey = 'history.recent';
  static const _wrongKey = 'history.wrong';
  static const _gestureKey = 'progress.confirmGesture';
  static const _sayItKey = 'progress.sayIt';
  static const _safetyKey = 'progress.safetyAck';

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

  bool get sayItEnabled {
    final v = _get(_sayItKey);
    return v is bool ? v : true;
  }

  Future<void> setSayItEnabled(bool v) => _set(_sayItKey, v);

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
    return _set(_wrongKey, _wrong.toList());
  }

  @override
  Future<void> clearWrong(String id) {
    _wrong.remove(id);
    return _set(_wrongKey, _wrong.toList());
  }
}
