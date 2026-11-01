# Android build notes

Nothing in this repository has been built with Gradle yet (the dev sandbox
cannot reach Google/Maven hosts), so the Android configuration below is
reasoned from plugin sources, not verified. `test/platform/android_build_test.dart`
pins the settings so they cannot regress silently.

## Run first (machine with the Android SDK)

```
flutter doctor -v
flutter build apk --debug
```

Then run the app on a device with a front camera (pose plugin, camera
permission, TTS). `flutter build apk --release` afterwards (APK is about 46 MB
bigger because the pose plugin bundles three MediaPipe models).

## Versions in use

| Part | Version | Where |
|---|---|---|
| Android Gradle Plugin | 9.1.0 | `android/settings.gradle.kts` |
| Kotlin Gradle plugin | 2.4.0 | `android/settings.gradle.kts` |
| Gradle wrapper | 9.3.1 | `android/gradle/wrapper/gradle-wrapper.properties` |
| JDK / JVM target | 17 | `android/app/build.gradle.kts` |
| minSdk | 24 (MediaPipe Tasks Vision) | `android/app/build.gradle.kts` |
| compileSdk | `maxOf(flutter.compileSdkVersion, 37)` | `android/app/build.gradle.kts` |

`flutter.compileSdkVersion` is 36 in Flutter 3.47; `permission_handler_android`
14.x declares `compileSdk = 37`, and an app compiled against a lower API fails
the AAR metadata check. Per the AGP 9.1 release notes AGP 9.1.x supports API
37 and lower, so 9.1.0 should accept it; if Gradle still warns that the
compileSdk is untested, move to AGP 9.1.1 (same Gradle 9.3.1 / JDK 17
requirements). The SDK Platform 37 must be installed
(`sdkmanager "platforms;android-37"`).

## The two required properties (`android/gradle.properties`)

```
android.builtInKotlin=false
android.newDsl=false
```

`flutter_mp_pose_landmarker` 0.1.9 and `flutter_tts` 4.2.5 are legacy
plugins: they apply `kotlin-android`, use `kotlinOptions {}` and the old
`android {}` DSL. AGP 9 rejects that unless built-in Kotlin and the new DSL
are switched off. Removing either line breaks the build with errors about
`kotlin-android` or `kotlinOptions`.

## If Gradle complains

1. `Dependency ... requires libraries and applications that depend on it to compile against version 37 or later`:
   the compileSdk line was lowered; restore `maxOf(flutter.compileSdkVersion, 37)`.
2. `Plugin 'kotlin-android' ... built-in Kotlin` or `kotlinOptions` errors:
   check the two properties above are present and uncommented.
3. "compileSdk 37 not tested with AGP 9.1.0": upgrade AGP to 9.1.1, or add
   `android.suppressUnsupportedCompileSdk=37` to `gradle.properties`.
4. A plugin's old `buildscript` (AGP 8.1.0 / Kotlin 1.8.22 in the pose
   plugin) failing to resolve or clashing: try one step at a time, in this
   order: `flutter clean` and `flutter pub get`; Gradle 9.3.1 with JDK 17 (check
   `JAVA_HOME`); then AGP 9.0.1 / Kotlin 2.3.20, which `permission_handler_android`
   itself uses.
5. Still failing for the pose plugin only: see the fallback in
   `docs/pose-plugin-evaluation.md` (the adapter isolates the plugin behind
   `PoseLandmarkerBackend`, so swapping it is one small file).
6. Duplicate-class or R8 errors in release: build debug first, then add keep
   rules for MediaPipe (`com.google.mediapipe.**`) if only release fails.
