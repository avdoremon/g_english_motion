import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// The app font must be Vietnamese-capable (Baloo 2). Glyph coverage itself is
/// checked by `python3 tools/check_font_vi.py` (fontTools); here we make sure
/// the four static weights exist and are declared in pubspec.yaml.
void main() {
  const weights = {'Regular': 400, 'Medium': 500, 'SemiBold': 600, 'Bold': 700};

  test('four Baloo 2 static files exist and are declared with weights', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    expect(pubspec, contains('family: Baloo 2'));
    expect(pubspec, isNot(contains('Fredoka')));
    weights.forEach((name, w) {
      final path = 'assets/fonts/Baloo2-$name.ttf';
      final f = File(path);
      expect(f.existsSync(), isTrue, reason: path);
      expect(f.lengthSync(), greaterThan(10000), reason: path);
      expect(
        RegExp('asset: $path\\s+weight: $w').hasMatch(pubspec),
        isTrue,
        reason: '$path declared with weight $w',
      );
    });
    expect(File('assets/fonts/OFL.txt').existsSync(), isTrue);
  });

  test('font files are static (no fvar table) TrueType', () {
    for (final name in weights.keys) {
      final b = File('assets/fonts/Baloo2-$name.ttf').readAsBytesSync();
      expect(
        String.fromCharCodes(b.sublist(0, 4)),
        anyOf('\u0000\u0001\u0000\u0000', 'true'),
      );
      // The table directory lists 4-byte tags; a variable font has "fvar".
      expect(String.fromCharCodes(b.take(2048)).contains('fvar'), isFalse);
    }
  });
}
