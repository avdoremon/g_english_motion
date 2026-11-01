import 'dart:convert';

import 'package:flutter/services.dart';

import '../content/curriculum.dart';

enum HintMode { full, partial, none }

class LevelConfig {
  const LevelConfig({
    required this.level,
    required this.questionCount,
    required this.baseTime,
    required this.choiceCount,
    required this.hints,
    required this.window,
  });

  final int level, questionCount, choiceCount;
  final Duration baseTime;
  final HintMode hints;
  final UnitWindow window;

  static const assetPath = 'assets/config/levels.json';

  static Future<List<LevelConfig>> load(AssetBundle b) async {
    try {
      final decoded = jsonDecode(await b.loadString(assetPath));
      if (decoded is! List) throw const FormatException('root must be a list');
      final out = [
        for (final e in decoded)
          if (e is Map<String, dynamic>)
            _parse(e)
          else
            throw const FormatException('entry must be an object'),
      ];
      if (out.isEmpty) throw const FormatException('no levels');
      return List.unmodifiable(out);
    } on FormatException catch (e) {
      throw FormatException('$assetPath: ${e.message}');
    }
  }

  static int _int(Map<String, dynamic> j, String k) {
    final v = j[k];
    if (v is! int) throw FormatException('missing or invalid "$k"');
    return v;
  }

  static T _enum<T extends Enum>(Map<String, dynamic> j, String k, List<T> vs) {
    final v = j[k];
    for (final e in vs) {
      if (e.name == v) return e;
    }
    throw FormatException('missing or invalid "$k"');
  }

  static LevelConfig _parse(Map<String, dynamic> j) => LevelConfig(
    level: _int(j, 'level'),
    questionCount: _int(j, 'questionCount'),
    baseTime: Duration(seconds: _int(j, 'baseTimeSeconds')),
    choiceCount: _int(j, 'choiceCount'),
    hints: _enum(j, 'hints', HintMode.values),
    window: _enum(j, 'window', UnitWindow.values),
  );
}
