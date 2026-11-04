import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final manifest = File('android/app/src/main/AndroidManifest.xml')
      .readAsStringSync();

  test('queries the TTS service (Android 11+ package visibility)', () {
    final queries = RegExp(r'<queries>[\s\S]*?</queries>')
        .firstMatch(manifest)!
        .group(0)!;
    expect(queries, contains('android.intent.action.TTS_SERVICE'));
    expect(queries, contains('android.intent.action.PROCESS_TEXT'));
  });

  test('SayIt: microphone permission and RecognitionService visibility', () {
    expect(manifest, contains('android.permission.RECORD_AUDIO'));
    final queries = RegExp(r'<queries>[\s\S]*?</queries>')
        .firstMatch(manifest)!
        .group(0)!;
    expect(queries, contains('android.speech.RecognitionService'));
  });

  test('no INTERNET permission is declared by the app (privacy)', () {
    expect(manifest, isNot(contains('android.permission.INTERNET')));
  });

  test('declares the camera permission and an optional front camera', () {
    expect(manifest, contains('android.permission.CAMERA'));
    expect(
      manifest,
      matches(RegExp(
        r'android\.hardware\.camera"\s+android:required="false"',
      )),
    );
    expect(
      manifest,
      matches(RegExp(
        r'android\.hardware\.camera\.front"\s+android:required="false"',
      )),
    );
  });

  test('app label is Tin Tin English', () {
    expect(manifest, contains('android:label="Tin Tin English"'));
  });
}
