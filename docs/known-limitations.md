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
- **Android build unverified.** No Gradle/Maven access in the dev sandbox, so
  no APK was ever built (AGP 9.1.0, Kotlin 2.4.0, compileSdk 37 against a
  plugin with AGP 8.1 / Kotlin 1.8.22). See
  [android-build-notes.md](android-build-notes.md) for the first commands and
  fixes. Plugin licence shows "unknown" on pub.dev and the APK grows by ~46 MB.

## Content and audio

- **No recorded audio.** Questions are read by the device text-to-speech and
  Vietnamese prompts are shown as captions only (no `.m4a` clips shipped).
- **Vocabulary is not teacher-reviewed.** Grade 1 units 1-2 are author-written
  for their topics; only 11 unit titles in the whole curriculum are confirmed.
  See [content/unit-map.md](content/unit-map.md).
- **Placeholder art.** Word pictures are generated placeholder cards (see
  `assets/images/LICENSES.md`); real artwork will replace them under the same
  file names.

## Not implemented yet

- **SayIt** (speech), **DragSpell** and **SkyShoot** modes: the content and
  question generator support their question forms, but there are no screens
  or round logic; only LaneJump is playable. Home has only a disabled SayIt placeholder.
- Grades 2-5 content directories are empty.

## Needs the user's device (plan Task 0 / Task 16)

- The measurement spike on a real phone with children aged 6-7 and 9-10:
  jump miss / false-fire rates, lane stepping, 20-minute thermal and fps run,
  cast latency to the TV, speech-recognition accuracy.
- Confirming on-device the points marked UNVERIFIED in
  [pose-plugin-evaluation.md](pose-plugin-evaluation.md) ("Verify on the first
  device run") and building with Gradle.
- Recorded landmark fixtures (`test/fixtures/landmarks/`) to replace the
  synthetic pose sequences used by the input tests.
