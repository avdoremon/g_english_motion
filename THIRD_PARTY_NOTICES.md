# Third-party notices

Direct dependencies of this app (`pubspec.yaml`), with the licence found in
each package's `LICENSE` file in the pub cache (versions as locked in
`pubspec.lock`). Transitive Dart and Android dependencies (CameraX, MediaPipe
Tasks Vision, the Flutter engine, ...) have their own licences and are not
listed one by one (`flutter pub deps` lists the Dart ones,
`./gradlew :app:dependencies` the Android ones). The app does not yet show an
in-app licence page; add one (`showLicensePage`) before a public release.

| Package | Version | Licence | Copyright holder |
|---|---|---|---|
| `flutter_mp_pose_landmarker` | 0.1.9 | Apache-2.0 (see note 1) | CareCode |
| `flutter_tts` | 4.2.5 | MIT | Daniel Lutton |
| `just_audio` | 0.10.6 | MIT | Ryan Heise and the project contributors |
| `permission_handler` | 13.0.2 | MIT | Baseflow |
| `wakelock_plus` | 1.8.2 | BSD-3-Clause | creativecreatorormaybenot |
| `shared_preferences` | 2.5.6 | BSD-3-Clause | The Flutter Authors |
| `cupertino_icons` | 1.0.9 | MIT | Vladimir Kharlampidi |
| `flutter_lints` (dev only) | 6.0.0 | BSD-3-Clause | The Flutter Authors |
| `shared_preferences_platform_interface` (dev only) | 2.4.2 | BSD-3-Clause | The Flutter Authors |

## Notes

1. **`flutter_mp_pose_landmarker`**: pub.dev shows the licence as "unknown"
   because the package's `LICENSE` file holds only the Apache-2.0 header
   ("Copyright 2025 CareCode ... Licensed under the Apache License, Version
   2.0"), not the full text, so pub's detector cannot match it. The plugin's
   `pubspec.yaml` declares `license: Apache-2.0`. Have the licence confirmed
   with the author before a public release.
2. **MediaPipe pose models.** The plugin bundles the three MediaPipe Pose
   Landmarker models (`pose_landmarker_lite.task`, `_full.task`,
   `_heavy.task`; about 46 MB in total) and the app ships them. They are
   Google MediaPipe models distributed under Apache-2.0 (per Google's
   MediaPipe model card; the plugin itself does not restate this, and it was
   not re-checked offline). Apache-2.0 requires keeping the licence text and
   notices with redistributed copies.
3. **Images.** The word pictures in `assets/images/` are project-owned
   placeholders; see `assets/images/LICENSES.md`.

The full licence texts are in each package's `LICENSE` file (pub cache:
`~/.pub-cache/hosted/pub.dev/<package>-<version>/LICENSE`).
