import 'dart:convert';

import 'package:flutter/services.dart';

import '../input/action_detector.dart';

/// One puppySays command: what the puppy says and which body action answers
/// it, for grades [minGrade]..[maxGrade].
class ActionDef {
  const ActionDef({
    required this.id,
    required this.command,
    required this.ttsText,
    required this.hintVi,
    required this.action,
    required this.minGrade,
    required this.maxGrade,
  });

  final String id, command, ttsText, hintVi;
  final PuppyAction action;
  final int minGrade, maxGrade;
}

/// The puppySays commands, loaded from `assets/config/actions.json`.
class ActionConfig {
  const ActionConfig(this._actions);

  final List<ActionDef> _actions;

  static const assetPath = 'assets/config/actions.json';

  /// Parses the asset; any problem is a [FormatException] naming the file.
  static Future<ActionConfig> load(AssetBundle b) async {
    try {
      final decoded = jsonDecode(await b.loadString(assetPath));
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('root must be an object');
      }
      final list = decoded['actions'];
      if (list is! List) {
        throw const FormatException('missing or invalid "actions"');
      }
      final out = <ActionDef>[];
      final ids = <String>{};
      for (final e in list) {
        if (e is! Map<String, dynamic>) {
          throw const FormatException('action must be an object');
        }
        final def = _parse(e);
        if (!ids.add(def.id)) {
          throw FormatException('duplicate action id "${def.id}"');
        }
        out.add(def);
      }
      return ActionConfig(List.unmodifiable(out));
    } on FormatException catch (e) {
      throw FormatException('$assetPath: ${e.message}');
    }
  }

  static String _str(Map<String, dynamic> j, String k) {
    final v = j[k];
    if (v is! String || v.isEmpty) {
      throw FormatException('missing or invalid "$k"');
    }
    return v;
  }

  static int _int(Map<String, dynamic> j, String k) {
    final v = j[k];
    if (v is! int) throw FormatException('missing or invalid "$k"');
    return v;
  }

  static ActionDef _parse(Map<String, dynamic> j) {
    final id = _str(j, 'id');
    final kinds = PuppyAction.values.where((a) => a.name == id);
    if (kinds.isEmpty) throw FormatException('unknown action id "$id"');
    final def = ActionDef(
      id: id,
      command: _str(j, 'command'),
      ttsText: _str(j, 'ttsText'),
      hintVi: _str(j, 'hintVi'),
      action: kinds.first,
      minGrade: _int(j, 'minGrade'),
      maxGrade: _int(j, 'maxGrade'),
    );
    if (def.minGrade > def.maxGrade) {
      throw FormatException('"$id": minGrade > maxGrade (grade range)');
    }
    return def;
  }

  /// The actions offered at [grade], in file order.
  List<ActionDef> forGrade(int grade) => [
    for (final a in _actions)
      if (a.minGrade <= grade && grade <= a.maxGrade) a,
  ];
}
