enum ModeKind { laneJump, dragSpell, skyShoot, sayIt }

class ContentItem {
  const ContentItem({
    required this.id,
    required this.word,
    required this.ttsText,
    this.image,
    this.syllables = 1,
    this.sentencePatterns = const [],
    this.distractorIds = const [],
    this.spokenVariants = const [],
    required this.modes,
  });

  final String id, word, ttsText;
  final String? image;
  final int syllables;
  final List<String> sentencePatterns, distractorIds, spokenVariants;
  final List<ModeKind> modes;

  /// Parses one item; throws [FormatException] (without file name) on bad data.
  factory ContentItem.fromJson(Map<String, dynamic> j) {
    String req(String k) {
      final v = j[k];
      if (v is! String || v.isEmpty) {
        throw FormatException('missing or invalid "$k"');
      }
      return v;
    }

    List<String> strs(String k) {
      final v = j[k];
      if (v == null) return const [];
      if (v is! List || v.any((e) => e is! String)) {
        throw FormatException('"$k" must be a list of strings');
      }
      return List<String>.unmodifiable(v.cast<String>());
    }

    final syl = j['syllables'] ?? 1;
    if (syl is! int) {
      throw const FormatException('"syllables" must be an int');
    }
    final img = j['image'];
    if (img != null && img is! String) {
      throw const FormatException('"image" must be a string');
    }
    final modes = <ModeKind>[];
    for (final m in strs('modes')) {
      final kind = ModeKind.values.where((e) => e.name == m);
      if (kind.isEmpty) throw FormatException('unknown mode "$m"');
      modes.add(kind.first);
    }
    return ContentItem(
      id: req('id'),
      word: req('word'),
      ttsText: req('ttsText'),
      image: img as String?,
      syllables: syl,
      sentencePatterns: strs('sentencePatterns'),
      distractorIds: strs('distractorIds'),
      spokenVariants: strs('spokenVariants'),
      modes: List.unmodifiable(modes),
    );
  }
}

class Unit {
  const Unit({
    required this.grade,
    required this.index,
    required this.id,
    required this.title,
    required this.items,
  });

  final int grade, index;
  final String id, title;
  final List<ContentItem> items;

  factory Unit.fromJson(Map<String, dynamic> j) {
    final grade = j['grade'], index = j['index'];
    final id = j['unit'], title = j['title'], items = j['items'];
    if (grade is! int) {
      throw const FormatException('missing or invalid "grade"');
    }
    if (index is! int) {
      throw const FormatException('missing or invalid "index"');
    }
    if (id is! String) {
      throw const FormatException('missing or invalid "unit"');
    }
    if (title is! String) {
      throw const FormatException('missing or invalid "title"');
    }
    if (items is! List) {
      throw const FormatException('missing or invalid "items"');
    }
    return Unit(
      grade: grade,
      index: index,
      id: id,
      title: title,
      items: List.unmodifiable([
        for (final e in items)
          if (e is Map<String, dynamic>)
            ContentItem.fromJson(e)
          else
            throw const FormatException('item must be an object'),
      ]),
    );
  }
}
