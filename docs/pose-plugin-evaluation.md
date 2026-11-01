# Pose plugin evaluation: `flutter_mp_pose_landmarker` 0.1.9

Date: 2026-11-01. Adopted per the product owner's rule "prefer existing
plugins over writing native code". Read from the pub cache
(`~/.pub-cache/hosted/pub.dev/flutter_mp_pose_landmarker-0.1.9/`, below `P/`).
Nothing here was run on a device: maven/gradle hosts are blocked in the dev
sandbox, so no APK was built. Items marked **UNVERIFIED** need a device run.

Adapter: `lib/input/plugin_pose_frame_source.dart` (mapping, permission,
lifecycle; unit-tested with a fake backend), `lib/input/mp_pose_landmarker_backend.dart`
(minimal real wrapper, untested), `lib/ui/shell/pose_camera_host.dart`
(platform view host).

## Facts (with source refs)

| Topic | Finding | Where |
|---|---|---|
| Dart API | Static `PoseLandmarker`: `setConfig`, `switchCamera`, `getCurrentCamera`, `resetCamera`, `pause/resumeDetection`, `request/checkCameraPermission`, `isPreviewMirrored`, `isEmulator`, `poseLandmarkStream`. No `start`/`stop`/`dispose`/`release` in Dart. | `P/lib/flutter_mp_pose_landmarker.dart:123-219` |
| Event payload | JSON string → `PoseLandMarker{timestampMs, landmarks, worldLandmarks, fps}`; landmark `x,y,z,visibility,presence` (missing → 0.0). No image size. A JSON decode failure is rethrown as a stream error. | `…landmarker.dart:7-41, 81-121, 209-219` |
| Camera start | Only when the EventChannel gets its first listener (`onListen` → `startCamera()` + `enableAnalysis()`); `onCancel` → `disableAnalysis()` + `releaseCamera()` (CameraX `unbindAll`). The Dart stream is one cached broadcast stream, so the camera runs while ≥1 Dart listener exists. | `P/android/.../FlutterMpPoseLandmarkerPlugin.kt:211-230`, `CameraManager.kt:422-429` |
| Release API | Native `releaseCamera` / `restoreCamera` methods exist but are not exposed in Dart; `restoreCamera` never answers its `result` (a call would hang). We release by cancelling the stream subscription. | `FlutterMpPoseLandmarkerPlugin.kt:89-96` |
| Preview view | Plugin registers platform view `camera_preview_view`; the factory returns the SAME `PreviewView` instance for every view it creates. The package ships no Dart widget (`NativeCameraPreview` is only in the example app). | `FlutterMpPoseLandmarkerPlugin.kt:163-180`, `P/example/lib/main.dart:407-431` |
| Preview needed? | CameraX always binds `Preview` (surface = that `PreviewView`) together with `ImageAnalysis`. The preview surface exists only once the view is attached via the platform view, so **we assume the view must be in the tree for frames to flow (UNVERIFIED)**. | `CameraManager.kt:46-54, 181-184, 225-230` |
| Camera | Front by default (`LENS_FACING_FRONT`); falls back to "any camera" (preview mirroring then reported false). Only a toggle (`switchCamera`), no "set front/back". | `FlutterMpPoseLandmarkerPlugin.kt:32`, `CameraManager.kt:56, 138-145, 217-245` |
| Number of poses | `setNumPoses` is never called → MediaPipe default **1 pose**. `DEFAULT_NUM_POSES = 1` is unused. If >1 were ever returned, all poses are flattened into one `landmarks` list (33 each). | `PoseLandmarkerHelper.kt:167-173, 531`; `CameraManager.kt:368-382` |
| Rotation | Each analysis frame is rotated upright by `imageInfo.rotationDegrees` before inference; `ImageAnalysis.targetRotation` is never set (defaults to the display rotation at bind time). | `PoseLandmarkerHelper.kt:326-357`, `CameraManager.kt:188-202` |
| Mirroring | `isFrontCamera` is passed but unused (only logged); the model sees the raw, UNMIRRORED CameraX analysis image. `isPreviewMirrored` concerns the preview only. ⇒ landmarks are unmirrored, matching our contract; adapter `landmarksMirrored = false`. | `PoseLandmarkerHelper.kt:265-266`, `CameraManager.kt:231, 303-306` |
| Coordinates | MediaPipe normalised image coordinates (0..1, y down, x by width, y by height; may fall slightly outside when off-frame). | `CameraManager.kt:374-380` |
| Confidence | Both `visibility` and `presence` sent; 0.0 when MediaPipe leaves them empty. Adapter uses min(visibility, presence), ignoring a 0.0 one. | `CameraManager.kt:370-373` |
| Timestamp | `SystemClock.uptimeMillis()` taken when the RESULT is delivered (not capture time), ms resolution. Adapter converts to µs and forces strictly increasing. | `CameraManager.kt:399`; `PoseLandmarkerHelper.kt:282-291` |
| Image size | Not sent (the helper knows it, `ResultBundle.inputImageWidth/Height`, but it is dropped). Analysis requested 4:3, default 640x480; app is landscape-only ⇒ adapter assumes 640/480 = 4:3 (not the 16:9 default). | `PoseLandmarkerHelper.kt:513`, `CameraManager.kt:63, 169-178` |
| Frame rate | Capture capped at **15 fps** (`CONTROL_AE_TARGET_FPS_RANGE`); the Dart `setConfig` cannot change it (native handler does not pass `fps`). | `CameraManager.kt:64, 101, 196-200`; `FlutterMpPoseLandmarkerPlugin.kt:50-72` |
| Model / delegate | `setConfig(delegate 0 CPU / 1 GPU, model 0 full / 1 lite / 2 heavy)`; no-op if the manager is missing (no error). GPU→CPU fallback only on a Java `RuntimeException`. We use CPU + lite. | `FlutterMpPoseLandmarkerPlugin.kt:50-72`, `PoseLandmarkerHelper.kt:205-237` |
| Permission | Native `requestCameraPermission` returns only a bool (no permanently-denied) and dereferences `activity!!`. It does NOT request automatically on listen. We use `permission_handler` instead and subscribe only after a grant. Plugin manifest adds `CAMERA` (app already declares it; no manifest change needed). | `FlutterMpPoseLandmarkerPlugin.kt:98-121`, `P/android/src/main/AndroidManifest.xml` |
| Errors | `NO_MANAGER` (manager failed to construct), `CAMERA_ERROR` (bind failed), `POSE_ERROR` (MediaPipe) arrive as stream errors; the adapter drops them and the game's frame watchdog handles silence. | `FlutterMpPoseLandmarkerPlugin.kt:218-221`, `CameraManager.kt:246-250, 415-420` |
| Lifecycle | `bindToLifecycle(activity)`: CameraX stops/restarts with the Activity's start/stop. `onDetachedFromActivity` (and config-change detach) disposes the manager and builds a new one with a new `PreviewView`. No "interrupted" event. | `CameraManager.kt:225-230, 338-347`; `FlutterMpPoseLandmarkerPlugin.kt:183-194, 232-243` |
| Emulator | `CameraManager` is used on emulators too (the CHANGELOG 0.1.4 mock path is no longer wired). | `FlutterMpPoseLandmarkerPlugin.kt:187-190` |
| Android build | Groovy `buildscript` with AGP **8.1.0**, Kotlin **1.8.22**; `apply plugin: kotlin-android`; `kotlinOptions { jvmTarget 1.8 }`; Java 1.8; compileSdk 34; minSdk 24; CameraX 1.4.2; `tasks-vision` 0.10.35; extra deps material 1.10.0, navigation 2.7.7, gson. Namespace `com.example.flutter_mp_pose_landmarker`. | `P/android/build.gradle:1-68` |
| APK size | Bundles all three models as assets: lite 5.8 MB, full 9.4 MB, heavy 30.7 MB (~46 MB). | `P/android/src/main/assets/` |
| Privacy | No network code in the Android sources (grep for http/URL/socket/INTERNET: none). | `P/android/src/main/` |

## This app's Android project vs the plugin

App (Flutter 3.47 template): AGP **9.1.0**, Kotlin Gradle plugin **2.4.0**
(`android/settings.gradle.kts`), Gradle **9.3.1** (wrapper), Java/JVM 17,
minSdk 24 (`android/app/build.gradle.kts`), and in `android/gradle.properties`
`android.builtInKotlin=false` + `android.newDsl=false` (template opt-outs for
legacy plugins).

What could conflict (all **UNVERIFIED** without a Gradle run):

1. Plugin `buildscript` classpath AGP 8.1.0 / KGP 1.8.22: in a Flutter
   multi-project build the root's AGP 9.1.0 / KGP 2.4.0 already on the
   classpath win; the old artifacts are still resolved (downloaded).
2. `apply plugin: "kotlin-android"` under AGP 9 works only because the app
   keeps `android.builtInKotlin=false`; removing that flag breaks this plugin.
3. `kotlinOptions {}` is deprecated in KGP 2.x (possibly an error in newer
   KGP). `flutter_tts` 4.2.5, already a dependency, uses the identical block,
   so this is not a new risk — if one fails both do.
4. `android.newDsl=false` must stay (legacy `android {}` DSL in the plugin).
5. JVM target 1.8 for the plugin vs 17 for the app: fine (per-module).
6. minSdk 24 matches; compileSdk 34 for a library is fine.

## Verdict

**Adopt, with eyes open; keep the fallback ready.** The plugin covers what
the game needs for a single child in front of the front camera, and the
adapter isolates it behind `PoseLandmarkerBackend`, so swapping it costs one
small file.

Risks:

- **Unverified publisher** (pub.dev publisher: none), tiny adoption (6 likes,
  ~190 downloads/30 days, pub points 140/160), fast-changing 0.1.x.
- **License shows "unknown" on pub.dev**: the LICENSE file is only the
  Apache-2.0 notice header ("Copyright 2025 CareCode"), not the full text, so
  pub's detector fails; the grant itself reads as Apache-2.0. Have it
  confirmed before release.
- **Single pose only**: the game's two-person handling (calibrator tracks,
  `PoseSession._pickPlayer`) degrades to "whichever person MediaPipe picks";
  a parent walking in can steal tracking (the game then pauses as "player
  lost").
- **15 fps cap**, not configurable from Dart: jump/lane timings were designed
  around ~30 fps (e.g. calibrator `_frameSlack` 40 ms, 100 ms uncertainty
  hold); needs device tuning.
- **Timestamps** are result-delivery time in ms, not capture time.
- **Camera control**: front by default, toggle only; no image size; no
  release call in Dart (cancel is the release); errors only as stream errors.
- **Preview view required (assumed)** and the plugin hands out ONE shared
  Android view ⇒ exactly one `PoseCameraHost` may be mounted at a time.
- **Rotation**: `targetRotation` is fixed at bind time; flipping the phone
  between landscapeLeft/Right mid-session may feed upside-down frames.
  Mitigation if seen on device: lock to one landscape orientation, or call
  `PoseLandmarker.resetCamera()` on orientation change.
- **APK +~46 MB** of models (heavy/full unused). Possible trim:
  `androidResources.ignoreAssetsPattern` in the app module (UNVERIFIED).
- **Gradle/AGP/Kotlin**: see the list above; the app's first Android build
  is the real test.

## Fallback plan

1. **Vendor/fork** the plugin (Apache-2.0 notice permits it) as a path
   dependency and fix: `setNumPoses(2)`, configurable fps, capture
   timestamps, image size in the payload, Dart `releaseCamera`, analysis-only
   binding (no preview requirement), `targetRotation` updates, modern Gradle
   (KTS, no `buildscript`). Only `MpPoseLandmarkerBackend` changes.
2. **Own Kotlin** on MediaPipe Tasks Vision following the retired channel
   contract (`docs/native-pose-channel.md` and
   `lib/input/mediapipe_frame_source.dart` as of commit `c14ffb3`).
3. **`google_mlkit_pose_detection` + `camera`**: also 33 BlazePose landmarks,
   single pose, more mature publisher; needs camera-image conversion in Dart
   and a new backend.

## Verify on the first device run

- Frames flow with `PoseCameraHost` at 1x1 / 1% opacity (and confirm they
  stop without it, to know whether the host is really required).
- Front camera chosen; landmarks unmirrored (raise the RIGHT hand: its x
  should be < 0.5 in the unmirrored image when facing the camera).
- Analysis aspect is 4:3 (else adjust `MpPoseLandmarkerBackend`).
- Camera released (LED off) on exit, result screen, and back; restarts on
  "play again" and after background/resume.
- `flutter build apk` with AGP 9.1 / KGP 2.4 succeeds.
