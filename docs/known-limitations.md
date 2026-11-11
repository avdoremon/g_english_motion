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

## UI kit and visual identity (Space Puppy re-skin)

- **Baloo 2 is bundled as four static instances** (Regular 400, Medium 500,
  SemiBold 600, Bold 700 in `assets/fonts/`, SIL OFL 1.1), cut from the
  upstream variable font with fontTools, so each `FontWeight` maps to its own
  file. Baloo 2 replaced Fredoka because Fredoka lacks Vietnamese diacritics;
  `tools/check_font_vi.py` and `test/ui/font_coverage_test.dart` guard the
  files. Roboto/sans-serif remain the generic fallback.
- **Space Puppy replaces the old mascot** (`lib/ui/mascot/space_pup_painter.dart`
  via `TinTin`); the previous mascot art is gone.
- **The app logo/launcher icon is still the Jump Star robot**; the redraw to
  match Space Puppy is pending.
- **Legacy text-theme slots are migrated.** `displayMedium`, `headlineMedium`,
  `titleLarge`, `titleMedium` and `bodyMedium` (old sizes 56/40/32/24/22) were
  removed from `AppTheme`; every screen now uses `AppTheme.textStyles`
  (display 56, title 48, heading 36, play 28, label 24). Remaining
  `Theme.of(context).textTheme` uses only read `bodyLarge` (= play, 28).
- **In-play text sizes (ruling).** Guidance, miss and hint text during play
  is Play 28 sp (SkyShoot "Trượt rồi! Bắn lại nhé" / "Nhảy hoặc chạm để bắn",
  the caption strip). Label 24 sp is allowed only for counters and HUD chips
  (SkyShoot "Lượt bắn" / "Kéo dây", the DragSpell held-tile chip). No
  `height` hacks or scale-down fitting are used for play guidance; SkyShoot's
  compact status row was made 8 dp taller instead (64 -> 72 at 800x360).
- `test/ui/no_hardcoded_style_test.dart` guards: no off-scale
  `fontSize` literals/constants and no `Color(`, `Color.fromARGB/RGBO` or
  `Colors.white/black` outside `app_theme.dart` and `*_painter.dart` files; it
  scans `lib/ui`, `lib/app` and `lib/main.dart` and self-tests its patterns.

## Content and audio

- **No recorded audio.** Questions are read by the device text-to-speech and
  Vietnamese prompts are shown as captions only (no `.m4a` clips shipped, so
  the voice depends on the phone's installed English TTS voice).
- **Vocabulary is not teacher-reviewed.** All 92 units (grades 1-5) have
  content. Unit titles and word lists were researched on 2026-11-04 from
  Vietnamese teaching sites (per-unit URLs in `docs/content/sources-grade<N>.md`),
  not from the printed books. Many pages were truncated, so some lists are
  partial and padded with related "fill" words (marked in the sources files);
  sentence patterns and spoken variants for new words are author-written.
  Check every unit against the printed textbook before release.
- **Placeholder art.** Word pictures are generated placeholder cards (see
  `assets/images/LICENSES.md`); real artwork will replace them under the same
  file names. Each card shows a neutral shape derived from a hash of the word
  (never its initial letter, which would let a child who knows the alphabet
  answer "which picture is ...?" without recognising the picture).

## Implemented but unverified on a device

- **DragSpell and SkyShoot** (grades 3-5) and **SayIt** have round
  logic, screens and tests, but have never run on a phone. SkyShoot's cast
  latency (250 ms) and sweep speed are placeholders until the Task 0 spike.
- **SayIt** uses the `speech_to_text` plugin restricted to on-device
  recognition (API 31+ and an installed English pack). If the phone has no
  on-device recogniser the entry is hidden; it never falls back to cloud.
  SayIt is **off until a parent switches it on** in the parent area, which is
  the only place the microphone is ever requested (that switch going off ->
  on is what asks the OS). Known small gaps: no message when the mic is
  permanently denied; SayIt stars are not saved.
- **Mode picker ("Chọn trò chơi")**: a grid next to "Chơi" on Home. It has up
  to 3 columns but drops to 2 (or 1) when titles would no longer fit on one
  line at the play size - under about 700 dp wide or at text scale 1.3 - and
  it scrolls: 9 tiles (8 modes with SayIt, plus "Ngẫu nhiên") need
  scrolling at 800x360.
  Modes not offered at the picked grade stay visible but disabled, with their
  grade range as the reason. "Trộn ngẫu nhiên" plays every camera mode valid
  for the grade (never SayIt). The choice is session state only (not stored):
  retry and next level keep it, going Home forgets it; "Chơi" always plays the
  grade's default mix. The SayIt tile appears only when Home shows "Luyện nói"
  and starts SayIt through its own path.
- **Đúng/Sai (yesNo)**: the left hand answers "Đúng", the right hand "Sai".
  The sides rely on the pose plugin labelling the person's OWN side (not the
  image side); this has not been verified on a device. `swapSides` on
  `HandSideDetector` is the single switch to flip it. The two big targets on
  the screen are the touch fallback.
- **yesNo: one answer per raise.** A hand that has answered stays latched
  until a reliable frame shows that wrist below the nose. A hand already up
  when the question appears, or held up from the previous round, therefore
  does not answer: the child must lower it and raise it again (the latch also
  survives landmark dropouts, lost/found player and failed frames).
- **yesNo hint size**: the "giơ tay trái/phải" hint is a Label at 24 sp,
  following the picker's secondary text.
- **yesNo level 1 asks 8 questions**, although the spec (§2) asked for at
  least 10: the level table is unchanged, so a 50 % guess weighs more there.
- **yesNo is guessable**: a true/false question is right 50 % of the time by
  chance, and the level's `questionCount` is unchanged, so a few lucky guesses
  can earn stars. False statements use the item's distractors, and an item
  without a sentence pattern shows the bare word as its statement.
- **Touch fallback** matrix (no camera/pose input): MemoryFlip and BalloonPop
  keep tap on the card/balloon (hold-pick frame); CatchIt has none (lane is
  body-driven only); yesNo keeps the two on-screen Đúng/Sai targets; LaneJump,
  DragSpell and SkyShoot unchanged. TTS speaks
  the target word as the prompt for MemoryFlip and BalloonPop.
- **New modes borrow items from adjacent units.** balloonPop, memoryFlip and
  catchIt are tagged on a subset of words, so an early unit can hold too few
  tagged items for a plan of 8. The generator then widens the content window
  (all units up to the current one, then the whole grade) until no picture
  would be asked more than twice. A widened pool is mixed without preferring
  the current unit, so a session may hold none of its own unit's words and may
  show words from units not reached yet. With a wrong-answer history an item
  can still be asked a third time when the pool sits exactly at the threshold.
- A SkyShoot round with no pull for 20 s ends as a timeout.
- DragSpell tray/slot cells are laid out from the text they must hold (about
  half an em per character at the 28 sp floor, never below the 56 px touch
  target), wrapping to more rows; on 800x360 the row height of long words
  stays >= 48 px but can be below the 56 px target. A word longer than its
  cell is drawn at the 28 sp floor and ellipsized rather than shrunk further.
- The "take a break" reminder repeats after every 20 minutes of play time,
  which is accumulated in the store across play flows and reset after 10
  minutes without play.
- The privacy-policy line in the parent area is plain text, not a link:
  there is no policy page yet (it will be a bundled local asset, no network).
- The system font setting is capped at 1.1x
  (`ClampedTextScale`): the play screens reserve fixed pixel heights for text.
- Gradle/AGP compatibility is verified by CI (debug APK builds); nothing has
  been run on a device.

## Not implemented yet

- LaneJump is not part of the grade 3-5 mix.
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

## Logo

- App icon, adaptive icon (incl. Android 13 themed) and splash use the "Jump Star" Tin Tin mark, generated by `tools/gen_logo.py` into `assets/branding/` and applied with `dart run flutter_launcher_icons` and `dart run flutter_native_splash:create`. **Both plugins reformat `AndroidManifest.xml` and drop `android:screenOrientation="sensorLandscape"`; restore it (`git checkout main -- android/app/src/main/AndroidManifest.xml`) after every run.**
- The in-app Tin Tin mascot (`lib/ui/mascot/tin_tin.dart`) and theme colours are unchanged; only the launcher icon and splash carry the new logo. The "i" dots in the wordmark are not stars yet.
