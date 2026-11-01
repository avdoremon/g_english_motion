import 'dart:convert';

import 'package:flutter/services.dart';

import 'models.dart';

const contentAssetPrefix = 'assets/content/';

/// Lists asset paths available in [bundle]. Overridable for tests.
typedef AssetLister = Future<List<String>> Function(AssetBundle bundle);

Future<List<String>> _manifestAssets(AssetBundle b) async =>
    (await AssetManifest.loadFromAssetBundle(b)).listAssets();

class ContentRepository {
  /// Validates global id uniqueness and that every distractor id exists.
  ContentRepository(List<Unit> units, {Map<Unit, String> sources = const {}})
    : _units = List.unmodifiable(units),
      _byId = _index(units, sources);

  final List<Unit> _units;
  final Map<String, ContentItem> _byId;

  static Map<String, ContentItem> _index(
    List<Unit> units,
    Map<Unit, String> sources,
  ) {
    final map = <String, ContentItem>{};
    final origin = <String, String>{};
    for (final u in units) {
      final src = sources[u] ?? 'unit ${u.id} (grade ${u.grade})';
      for (final it in u.items) {
        if (map.containsKey(it.id)) {
          throw ArgumentError(
            'Duplicate content id "${it.id}" in $src (first in ${origin[it.id]})',
          );
        }
        map[it.id] = it;
        origin[it.id] = src;
      }
    }
    for (final u in units) {
      final src = sources[u] ?? 'unit ${u.id} (grade ${u.grade})';
      for (final it in u.items) {
        for (final d in it.distractorIds) {
          if (!map.containsKey(d)) {
            throw ArgumentError(
              'Item "${it.id}" in $src has unknown distractor id "$d"',
            );
          }
        }
      }
    }
    return map;
  }

  static Future<ContentRepository> loadFromAssets(
    AssetBundle bundle, {
    AssetLister listAssets = _manifestAssets,
  }) async {
    final paths =
        (await listAssets(bundle))
            .where(
              (p) => p.startsWith(contentAssetPrefix) && p.endsWith('.json'),
            )
            .toList()
          ..sort();
    final units = <Unit>[];
    final sources = <Unit, String>{};
    for (final p in paths) {
      try {
        final decoded = jsonDecode(await bundle.loadString(p));
        if (decoded is! Map<String, dynamic>) {
          throw const FormatException('root must be an object');
        }
        final u = Unit.fromJson(decoded);
        units.add(u);
        sources[u] = p;
      } on FormatException catch (e) {
        throw FormatException('$p: ${e.message}');
      }
    }
    return ContentRepository(units, sources: sources);
  }

  /// Units of [grade], ordered by unit index.
  List<Unit> unitsFor(int grade) =>
      _units.where((u) => u.grade == grade).toList()
        ..sort((a, b) => a.index.compareTo(b.index));

  ContentItem byId(String id) {
    final it = _byId[id];
    if (it == null) throw StateError('Unknown content id "$id"');
    return it;
  }
}
