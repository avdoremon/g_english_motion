import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Lint-style guard: screens must take sizes and colours from
/// `AppTheme` (tokens / `AppTheme.textStyles`), not hard-code them.
void main() {
  // Allow-list (documented): files that may define raw colours.
  //  - app_theme.dart: the single source of tokens.
  //  - *_painter.dart: CustomPainters (mascot art) carry their own palette.
  bool allowedForColor(String path) =>
      path.endsWith('theme/app_theme.dart') || path.endsWith('_painter.dart');
  bool allowedForFontSize(String path) => path.endsWith('theme/app_theme.dart');

  // The five-size type scale (sp).
  const scale = {56, 48, 36, 28, 24};

  final files = Directory('lib/ui')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('no off-scale fontSize literals in lib/ui', () {
    final offenders = <String>[];
    final re = RegExp(r'fontSize:\s*(\d+(?:\.\d+)?)');
    for (final f in files) {
      if (allowedForFontSize(f.path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        for (final m in re.allMatches(lines[i])) {
          final v = double.parse(m.group(1)!);
          if (!scale.contains(v.round()) || v != v.roundToDouble()) {
            offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
          }
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });

  test('no Color(0x...) literals in lib/ui outside the allow-list', () {
    final offenders = <String>[];
    for (final f in files) {
      if (allowedForColor(f.path)) continue;
      final lines = f.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('Color(0x')) {
          offenders.add('${f.path}:${i + 1}: ${lines[i].trim()}');
        }
      }
    }
    expect(offenders, isEmpty, reason: offenders.join('\n'));
  });
}
