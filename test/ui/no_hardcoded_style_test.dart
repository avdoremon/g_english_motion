import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lint-style guard: screens must take sizes and colours from
/// `AppTheme` (tokens / `AppTheme.textStyles`), not hard-code them.

/// The five-size type scale (sp).
const _scale = {56, 48, 36, 28, 24};

final _fontSize = RegExp(r'fontSize\s*[:=]\s*(\d+(?:\.\d+)?)');
final _colorLiteral = RegExp(
  r'\bColor\(|\bColor\.from(?:ARGB|RGBO)\(|\bColors\.(?:white|black)\w*',
);

/// Returns the offending lines of [source] (`line N: text`).
List<String> scanFontSizes(String source) {
  final out = <String>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    for (final m in _fontSize.allMatches(lines[i])) {
      final v = double.parse(m.group(1)!);
      if (v != v.roundToDouble() || !_scale.contains(v.round())) {
        out.add('line ${i + 1}: ${lines[i].trim()}');
      }
    }
  }
  return out;
}

List<String> scanColors(String source) {
  final out = <String>[];
  final lines = source.split('\n');
  for (var i = 0; i < lines.length; i++) {
    if (_colorLiteral.hasMatch(lines[i])) {
      out.add('line ${i + 1}: ${lines[i].trim()}');
    }
  }
  return out;
}

void main() {
  // Allow-list (documented):
  //  - theme/app_theme.dart: the single source of tokens.
  //  - *_painter.dart: CustomPainters (mascot art) carry their own palette.
  bool allowedForColor(String path) =>
      path.endsWith('theme/app_theme.dart') || path.endsWith('_painter.dart');
  bool allowedForFontSize(String path) => path.endsWith('theme/app_theme.dart');

  final files = <File>[
    ...Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')),
    ...Directory('lib/app')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart')),
    File('lib/main.dart'),
  ];

  group('scanner self-test (fixtures)', () {
    test('fontSize: off-scale literal, const declaration, decimals', () {
      expect(scanFontSizes('style: TextStyle(fontSize: 22)'), hasLength(1));
      expect(scanFontSizes('static const double fontSize = 30;'), hasLength(1));
      expect(scanFontSizes('copyWith(fontSize:30.5)'), hasLength(1));
    });
    test('fontSize: on-scale and non-literal values pass', () {
      for (final v in _scale) {
        expect(scanFontSizes('TextStyle(fontSize: $v)'), isEmpty);
      }
      expect(scanFontSizes('copyWith(fontSize: size)'), isEmpty);
      expect(scanFontSizes('style.fontSize ?? 1'), isEmpty);
    });
    test('colours: Color(, Color.fromARGB/RGBO, Colors.white/black', () {
      expect(scanColors('c = const Color(0xFF000000);'), hasLength(1));
      expect(scanColors('c = Color.fromARGB(1, 2, 3, 4);'), hasLength(1));
      expect(scanColors('c = Color.fromRGBO(1, 2, 3, 0.5);'), hasLength(1));
      expect(scanColors('c = Colors.white;'), hasLength(1));
      expect(scanColors('c = Colors.black87;'), hasLength(1));
    });
    test('colours: tokens and transparent pass', () {
      expect(scanColors('c = AppTheme.surface;'), isEmpty);
      expect(scanColors('c = Colors.transparent;'), isEmpty);
      expect(scanColors('final Color? fill;'), isEmpty);
    });
  });

  test('no off-scale fontSize literals in lib/ui, lib/app, lib/main.dart', () {
    final offenders = <String>[
      for (final f in files)
        if (!allowedForFontSize(f.path))
          for (final o in scanFontSizes(f.readAsStringSync())) '${f.path}: $o',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('no hard-coded colours outside the allow-list', () {
    final offenders = <String>[
      for (final f in files)
        if (!allowedForColor(f.path))
          for (final o in scanColors(f.readAsStringSync())) '${f.path}: $o',
    ];
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
