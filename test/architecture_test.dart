import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Privacy guard: camera/mic data never leaves the device, so only lib/ads/
/// may touch network libraries.
final _forbidden = <RegExp>[
  RegExp(r'package:http\b'),
  RegExp(r'package:dio\b'),
  RegExp(r'HttpClient'),
  RegExp(r'WebSocket'),
];

List<String> findViolations(Directory lib) {
  final violations = <String>[];
  if (!lib.existsSync()) return violations;
  for (final entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final normalized = entity.path.replaceAll('\\', '/');
    if (normalized.contains('/lib/ads/') || normalized.startsWith('lib/ads/')) {
      continue;
    }
    final content = entity.readAsStringSync();
    for (final pattern in _forbidden) {
      if (pattern.hasMatch(content)) {
        violations.add('$normalized matches ${pattern.pattern}');
      }
    }
  }
  return violations;
}

void main() {
  test('no network libraries outside lib/ads/', () {
    expect(findViolations(Directory('lib')), isEmpty);
  });

  test('scanner catches a violating file and ignores lib/ads/', () {
    final tmp = Directory.systemTemp.createTempSync('arch');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final lib = Directory('${tmp.path}/lib')..createSync();
    File('${lib.path}/bad.dart')
        .writeAsStringSync("import 'package:http/http.dart';");
    Directory('${lib.path}/ads').createSync();
    File('${lib.path}/ads/ok.dart')
        .writeAsStringSync("import 'package:dio/dio.dart';");
    final found = findViolations(lib);
    expect(found, hasLength(1));
    expect(found.single, contains('bad.dart'));
  });
}
