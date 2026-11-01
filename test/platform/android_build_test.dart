import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Pins the Android build settings that cannot be exercised without a Gradle
/// host (see docs/android-build-notes.md). A regression here would only show
/// up as a failed `flutter build apk`.
void main() {
  String read(String p) => File(p).readAsStringSync();

  /// `key=value` lines of a .properties file (comments and blanks skipped).
  Map<String, String> props(String p) {
    final out = <String, String>{};
    for (final raw in read(p).split('\n')) {
      final line = raw.trim();
      if (line.isEmpty || line.startsWith('#')) continue;
      final i = line.indexOf('=');
      if (i > 0)
        out[line.substring(0, i).trim()] = line.substring(i + 1).trim();
    }
    return out;
  }

  final app = read('android/app/build.gradle.kts');
  final gradleProps = props('android/gradle.properties');

  test(
    'compileSdk is max(flutter default, 37) for permission_handler_android',
    () {
      // permission_handler_android 14.x compiles against API 37; a smaller app
      // compileSdk fails the AAR metadata check.
      expect(
        app,
        matches(
          RegExp(
            r'compileSdk\s*=\s*maxOf\(\s*flutter\.compileSdkVersion\s*,\s*37\s*\)',
          ),
        ),
      );
      expect(app, isNot(contains('compileSdk = flutter.compileSdkVersion')));
    },
  );

  test('minSdk stays 24 (MediaPipe Tasks Vision)', () {
    expect(app, matches(RegExp(r'minSdk\s*=\s*24\b')));
  });

  test('legacy-plugin opt-outs stay on (pose plugin, flutter_tts)', () {
    // Both plugins apply `kotlin-android` and the old `android {}` DSL, which
    // AGP 9 only accepts with these two flags.
    expect(gradleProps['android.builtInKotlin'], 'false');
    expect(gradleProps['android.newDsl'], 'false');
  });

  test('AGP supports the compileSdk in use (9.1+ for API 37)', () {
    final m = RegExp(r'"com\.android\.application"\)\s*version\s*"(\d+)\.(\d+)')
        .firstMatch(read('android/settings.gradle.kts'));
    expect(
      m,
      isNotNull,
      reason: 'AGP version not found in settings.gradle.kts',
    );
    final major = int.parse(m!.group(1)!), minor = int.parse(m.group(2)!);
    expect(
      major > 9 || (major == 9 && minor >= 1),
      isTrue,
      reason: 'AGP 9.1 is the first line documented to support API 37',
    );
  });

  test('build notes document the properties and the first command', () {
    final notes = read('docs/android-build-notes.md');
    expect(notes, contains('flutter build apk --debug'));
    expect(notes, contains('android.builtInKotlin=false'));
    expect(notes, contains('android.newDsl=false'));
  });
}
