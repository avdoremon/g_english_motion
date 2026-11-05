abstract class HistoryStore {
  /// Most recently asked item ids, oldest first (most recent last).
  List<String> recentIds();
  Set<String> wrongIds();
  Future<void> recordAsked(List<String> ids);
  Future<void> markWrong(String id);
  Future<void> clearWrong(String id);
}

class InMemoryHistoryStore implements HistoryStore {
  static const maxRecent = 200;

  final List<String> _recent = [];
  final Set<String> _wrong = {};

  @override
  List<String> recentIds() => List.unmodifiable(_recent);

  @override
  Set<String> wrongIds() => Set.unmodifiable(_wrong);

  @override
  Future<void> recordAsked(List<String> ids) async {
    for (final id in ids) {
      _recent.remove(id);
      _recent.add(id);
    }
    if (_recent.length > maxRecent) {
      _recent.removeRange(0, _recent.length - maxRecent);
    }
  }

  @override
  Future<void> markWrong(String id) async => _wrong.add(id);

  @override
  Future<void> clearWrong(String id) async => _wrong.remove(id);
}
