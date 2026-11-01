# g_english_motion
Learn English with Motion Game

## Requirements

- Flutter stable **3.47.9** (Dart 3.13.7), pinned in `pubspec.yaml` (`environment.flutter`).
- Android only.

## Development

```
flutter pub get
flutter analyze
flutter test
```

Privacy: camera/mic data never leaves the device. Outside `lib/ads/` no file may import network libraries (enforced by `test/architecture_test.dart`).
