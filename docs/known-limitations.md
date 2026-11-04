# Known limitations

What is NOT done or NOT verified yet. Details live in the linked documents;
this page only summarises them so nothing is merged unknowingly.

## Pose input (plugin `flutter_mp_pose_landmarker` 0.1.9)

Full facts and sources: [pose-plugin-evaluation.md](pose-plugin-evaluation.md).

- **One pose per frame.** A second person cannot be tracked or ignored by
  position; whoever MediaPipe picks is "the player". The multi-person logic in
  `Calibrator` and `PoseSession` is only exercised by synthetic tests.
- **About 15 fps**, fixed by the plugin, with timestamps taken when the result
  arrives (not at capture). The input layer (jump, raise-hands, calibration,
  lane tracking, player-lost) uses timestamp windows only and has synthetic
  15 fps tests, but thresholds are not tuned on real data.
- **4:3 image assumed.** The plugin does not report the analysis image size;
  the adapter assumes 640x480, which sets the lane width in x.
- **The camera preview view must be on screen** (1x1 `PoseCameraHost`) for
  frames to flow (assumed from the plugin source, not run).
- **Slow drift can false-fire a jump.** The jump detector ignores body drift
  up to about 0.025 per second, but between that rate and the firing
  threshold a slow, steady rise (child leaning, phone sliding) looks the same
  as a slow real jump and can fire. This is inherent (the two are
  indistinguishable from the pose alone); the threshold needs tuning on real
  recordings.
- **Camera trouble is handled, not cured.** No frame for 5 s, plugin errors
  with no frame for 5 s (also during play), or a calibration that does not
  finish in 30 s end in a "Camera không hoạt động" screen (retry / home); the
  cause is only logged (`GameController: camera problem: ...`). Timings are
  untested on a device.
- **The 3 s close timeout only logs.** When leaving a game, the app waits at
  most 3 s for the old camera to be released (`closeTimeout`), then logs
  `close timed out` and starts the next flow anyway. If the old stop finishes
  late it can unbind the NEW camera (CameraX `unbindAll` on the plugin's
  shared stream), leaving the next game without frames (the camera-problem
  screen then appears after 5 s; Retry fixes it).
- **Android build unverified.** No Gradle/Maven access in the dev sandbox, so
  no APK was ever built here. The app uses AGP 9.1.0 / Kotlin 2.4.0 /
  compileSdk 37, while the pose plugin's own `buildscript` pins AGP 8.1.0 /
  Kotlin 1.8.22 and uses `kotlinOptions {}` (as does `flutter_tts`); whether
  the two coexist (with `android.builtInKotlin=false` and `android.newDsl=false`)
  is **unverified**. The `build-android` job in `.github/workflows/ci.yml`
  (`flutter build apk --debug`) is the first real check; read its result
  before relying on this. See [android-build-notes.md](android-build-notes.md)
  for the first commands and fixes.
- **Plugin licence wording.** pub.dev shows "unknown" because the plugin's
  `LICENSE` file holds only the Apache-2.0 header; its `pubspec.yaml` declares
  Apache-2.0. See [../THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md).
- **APK size.** The plugin bundles three MediaPipe models (+46 MB; the app
  uses only the lite one). An asset exclude can drop the other two for a
  release build; see "Optional release size trim" in
  [android-build-notes.md](android-build-notes.md) (not applied).

## Content and audio

- **No recorded audio.** Questions are read by the device text-to-speech and
  Vietnamese prompts are shown as captions only (no `.m4a` clips shipped, so
  the voice depends on the phone's installed English TTS voice).
- **Vocabulary is not teacher-reviewed.** Grade 1 units 1-2 are author-written
  for their topics; only 11 unit titles in the whole curriculum are confirmed.
  See [content/unit-map.md](content/unit-map.md).
- **Placeholder art.** Word pictures are generated placeholder cards (see
  `assets/images/LICENSES.md`); real artwork will replace them under the same
  file names.

## Implemented but unverified on a device

- **DragSpell and SkyShoot** (grade 3 units 1-2 only) and **SayIt** have round
  logic, screens and tests, but have never run on a phone. SkyShoot's cast
  latency (250 ms) and sweep speed are placeholders until the Task 0 spike.
- **SayIt** uses the `speech_to_text` plugin restricted to on-device
  recognition (API 31+ and an installed English pack). If the phone has no
  on-device recogniser the entry is hidden; it never falls back to cloud.
  The parent must switch it on in settings, which is when the mic permission is
  requested. Known small gaps: no message when the mic is permanently denied;
  SayIt stars are not saved.
- A SkyShoot round with no pull for 20 s ends as a timeout.
- DragSpell words of 11+ letters can drop below 48 px tiles on 800x360.
- Gradle/AGP compatibility is verified by CI (debug APK builds); nothing has
  been run on a device.

## Not implemented yet

- Grade 3 units 3+, grades 1-2 units 3+, grades 4-5 content (Home shows them
  as coming soon). LaneJump is not part of the grade 3-5 mix.
- Real art, recorded audio, ads/Families compliance (Task 24).

## Needs the user's device (plan Task 0 / Task 16)

- The measurement spike on a real phone with children aged 6-7 and 9-10:
  jump miss / false-fire rates, lane stepping, 20-minute thermal and fps run,
  cast latency to the TV, speech-recognition accuracy.
- Confirming on-device the points marked UNVERIFIED in
  [pose-plugin-evaluation.md](pose-plugin-evaluation.md) ("Verify on the first
  device run") and building with Gradle.
- Recorded landmark fixtures (`test/fixtures/landmarks/`) to replace the
  synthetic pose sequences used by the input tests.
