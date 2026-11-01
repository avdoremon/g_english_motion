# g_english_motion (Tin Tin English)

Learn English with a motion game: primary-school vocabulary (Global Success,
grades 1-5), played by standing in front of a phone camera. The child steps
left/right into a lane to pick an answer and jumps (or raises both hands) to
confirm. The phone can be cast to a TV.

## Status

**Phase 1 slice** (code complete, not yet tested on a device):

- Playable: **LaneJump** for grade 1 (units 1-2), levels with hints, stars,
  parent area, break reminder, camera problem screen.
- Not done: SayIt (speech), DragSpell, SkyShoot screens, grades 2-5 content,
  recorded audio (the phone's text-to-speech is used).
- Never built with Gradle yet in the dev sandbox; the CI job `build-android`
  is the first real Android build. Everything else that is unverified is
  listed in [docs/known-limitations.md](docs/known-limitations.md).

## Requirements

- Flutter stable **3.47.9** (Dart 3.13.7), pinned in `pubspec.yaml`
  (`environment.flutter`) and in `.github/workflows/ci.yml`.
- Android only (landscape, front camera, minSdk 24). For building: JDK 17 and
  the Android SDK with platform 37 (see
  [docs/android-build-notes.md](docs/android-build-notes.md)).

## Setup, test, run

```
flutter pub get
flutter analyze
flutter test            # all tests, no device needed (fake camera and audio)
flutter build apk --debug
```

Run on a phone with a front camera (USB debugging on, `adb devices` lists it):

```
flutter run -d <device-id>
```

The first Play asks for the camera permission. Useful logs:

```
adb logcat -s flutter CameraManager PoseLandmarkerPlugin PoseLandmarkerHelper
```

`flutter` carries the app's `debugPrint` messages (for example
`GameController: camera problem: ...` and `close timed out`); the other tags
come from the pose plugin's native side.

## Documents

- [docs/android-build-notes.md](docs/android-build-notes.md): Gradle / AGP /
  Kotlin versions, required properties, what to try when the build fails.
- [docs/known-limitations.md](docs/known-limitations.md): what is not done or
  not verified.
- [docs/pose-plugin-evaluation.md](docs/pose-plugin-evaluation.md): why the
  `flutter_mp_pose_landmarker` plugin is used, what it does and its risks.
- [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md): dependencies and licences.
- `docs/superpowers/`: product spec and implementation plan.

## Privacy

Camera and microphone data are processed **on the device only** and are never
stored or sent anywhere: frames are turned into pose landmarks in memory and
dropped. No file in `lib/` may import network libraries; this is enforced by
`test/architecture_test.dart` (the only exception is a future `lib/ads/`).
