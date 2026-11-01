import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Privacy guard: camera/mic data never leaves the device, so only lib/ads/
/// may touch network libraries, and no network package may be a dependency.
final _forbidden = <RegExp>[
  RegExp(r'package:http\b'),
  RegExp(r'package:dio\b'),
  RegExp(r'package:web_socket_channel\b'),
  RegExp(r'package:grpc\b'),
  RegExp(r'package:firebase'),
  RegExp(r'package:cloud_firestore\b'),
  RegExp(r'HttpClient'),
  RegExp(r'HttpServer'),
  RegExp(r'WebSocket'),
  RegExp(r'\bRawSocket\b'),
  RegExp(r'\bRawSecureSocket\b'),
  RegExp(r'\bSecureSocket\b'),
  RegExp(r'\bSocket\b'),
  RegExp(r'\bRawDatagramSocket\b'),
];

/// Packages that must never appear in pubspec.yaml (no allow-list).
final _forbiddenDependencies = <RegExp>[
  RegExp(r'^http$'),
  RegExp(r'^dio$'),
  RegExp(r'^web_socket_channel$'),
  RegExp(r'^grpc$'),
  RegExp(r'^firebase(_.*)?$'),
  RegExp(r'^cloud_firestore$'),
];

class ScanResult {
  ScanResult(this.violations, this.scanned);
  final List<String> violations;

  /// Number of .dart files that were actually checked.
  final int scanned;
}

ScanResult scan(Directory lib) {
  final violations = <String>[];
  var scanned = 0;
  if (!lib.existsSync()) return ScanResult(violations, scanned);
  for (final entity in lib.listSync(recursive: true)) {
    if (entity is! File || !entity.path.endsWith('.dart')) continue;
    final normalized = entity.path.replaceAll('\\', '/');
    if (normalized.contains('/lib/ads/') || normalized.startsWith('lib/ads/')) {
      continue;
    }
    scanned++;
    final content = entity.readAsStringSync();
    for (final pattern in _forbidden) {
      if (pattern.hasMatch(content)) {
        violations.add('$normalized matches ${pattern.pattern}');
      }
    }
  }
  return ScanResult(violations, scanned);
}

/// Dependency names declared in the dependencies/dev_dependencies/
/// dependency_overrides sections of a pubspec.
List<String> pubspecViolations(String pubspec) {
  final out = <String>[];
  var inDeps = false;
  for (final line in pubspec.split('\n')) {
    if (RegExp(r'^\S').hasMatch(line)) {
      inDeps = RegExp(r'^(dependencies|dev_dependencies|dependency_overrides):')
          .hasMatch(line);
      continue;
    }
    if (!inDeps) continue;
    final m = RegExp(r'^  ([A-Za-z0-9_]+):').firstMatch(line);
    if (m == null) continue;
    final name = m.group(1)!;
    if (_forbiddenDependencies.any((p) => p.hasMatch(name))) {
      out.add('pubspec.yaml depends on $name');
    }
  }
  return out;
}

void main() {
  test('no network libraries outside lib/ads/', () {
    final r = scan(Directory('lib'));
    expect(
      r.scanned,
      greaterThan(0),
      reason: 'lib/ missing or nothing scanned',
    );
    expect(r.violations, isEmpty);
  });

  test('pubspec.yaml has no network dependencies', () {
    final file = File('pubspec.yaml');
    expect(file.existsSync(), isTrue);
    final text = file.readAsStringSync();
    expect(text, contains('dependencies:'));
    expect(pubspecViolations(text), isEmpty);
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
    final r = scan(lib);
    expect(r.violations, hasLength(1));
    expect(r.violations.single, contains('bad.dart'));
    expect(r.scanned, 1);
  });

  for (final snippet in [
    "import 'package:web_socket_channel/web_socket_channel.dart';",
    "import 'package:grpc/grpc.dart';",
    "import 'package:firebase_core/firebase_core.dart';",
    'final s = await Socket.connect(h, 1);',
    'final s = await RawSocket.connect(h, 1);',
    'final s = await HttpServer.bind(h, 1);',
  ]) {
    test('scanner flags: $snippet', () {
      final tmp = Directory.systemTemp.createTempSync('arch');
      addTearDown(() => tmp.deleteSync(recursive: true));
      final lib = Directory('${tmp.path}/lib')..createSync();
      File('${lib.path}/x.dart').writeAsStringSync(snippet);
      expect(scan(lib).violations, hasLength(1));
    });
  }

  test('scanning a missing lib/ scans nothing (the real test then fails)', () {
    expect(scan(Directory('/nonexistent/lib')).scanned, 0);
  });

  test('pubspec scanner flags network packages', () {
    const bad = '''
name: x
dependencies:
  flutter:
    sdk: flutter
  http: ^1.0.0
  firebase_core: ^3.0.0
dev_dependencies:
  grpc: ^4.0.0
flutter:
  assets:
    - http
''';
    expect(pubspecViolations(bad), [
      'pubspec.yaml depends on http',
      'pubspec.yaml depends on firebase_core',
      'pubspec.yaml depends on grpc',
    ]);
  });
}
