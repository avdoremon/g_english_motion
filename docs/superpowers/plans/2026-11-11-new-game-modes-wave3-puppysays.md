# Wave 3: ActionDetector + puppySays "Theo Pup" + release hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `puppySays` mode (grades 1–2): a spoken command ("Jump!") names one of four body actions (jump, hands up, clap, squat); the round is correct when the camera sees that action. It ships **disabled by default** behind a parent-settings switch because the detector thresholds are unverified on a device. Also prepare a release build (R8 rules, signing from `key.properties`, CI release job).

**Architecture:** A new `ActionDetector` (composing `JumpDetector`, `RaiseHandsDetector` and two new geometric detectors) feeds a new `ActionPerformed(action)` event through `PoseSession`. A new `ActionQuestion`/`QuestionForm.doAction` is generated from `assets/config/actions.json`; `ActionRound` never returns `RoundResult.wrong`. Gating mirrors how SayIt is gated.

**Tech Stack:** Flutter 3.47/Dart, existing pose pipeline, Gradle (AGP 9.1) for Task 6.

**Spec:** `docs/superpowers/specs/2026-11-07-new-game-modes-design.md` (§2 puppySays, §3.3 ActionDetector, §6 risks, §7 decision 4). Model structure on `docs/superpowers/plans/2026-11-11-new-game-modes-wave2-yesno.md`.

## Global Constraints

- Round contract (`lib/modes/round.dart`): events before tick; clock stops while the player is lost; result set once; zero/negative tick ignored; oversize tick clamps and ends as `RoundResult.timeout` (neutral "Hết giờ").
- puppySays has NO "wrong" outcome: other actions, silence or doubtful frames never produce `RoundResult.wrong`; the round ends with the neutral timeout plus the hint "Pup chưa thấy rõ… thử lại nhé".
- The command is the prompt and may be shown and spoken (it names the action to perform, not an answer to guess).
- The mode is OFF by default: `ProgressStore.puppySaysEnabled` defaults to false (corrupt value reads false); when off, puppySays is absent from the picker, from the "Ngẫu nhiên" shuffle, and a `GameController` built with `mode: puppySays` falls back to the default mix.
- `assets/config/actions.json` (NOT under `assets/content/`, whose loader and validity test parse every file as a Unit). A missing or malformed actions file must not stop the app: the mode simply stays unavailable.
- Touch targets ≥ 56 dp; play text ≥ 28 sp (Label 24 only for counters/HUD chips); Wave 0 lint (`test/ui/no_hardcoded_style_test.dart`): font sizes only {56,48,36,28,24}, no `Color(`/`Colors.white|black` outside `app_theme.dart` and `*_painter.dart`; no overflow at 800×360 and 1280×720 including `textScaler` 1.3.
- No new packages; no network libraries; level table, `questionCount`, star thresholds, progress keyed by (grade, level) and the default "Chơi" mix unchanged; camera images are never shown or stored.
- Flutter is at `/home/claude/flutter/bin/flutter`. Never run `dart format` on the whole repo; no secrets or keystores in the repo.

## Review Focus

- A pose held across questions (hands up, squat) must not auto-answer the next command: each action fires once per performance and re-arms only after the pose is released. Test in Task 1.
- Two actions in one frame (jump with hands up): both are reported; the round accepts the one it asked for and ignores the other without penalty. Tests in Tasks 1 and 3.
- The child absent at round start (LevelSession drops `PlayerLost` outside `playing`): the round waits, nothing is graded or timed out. Test in Task 4.
- Flag off: the mode is unreachable through picker, shuffle, saved selection and direct `GameController(mode:)`. Tests in Tasks 3–5.
- `actions.json` missing/malformed/duplicate ids: app starts, mode unavailable. Test in Task 3.

---

### Task 1: ActionDetector (clap, squat, composition)

**Files:**
- Create: `lib/input/action_detector.dart`, `lib/input/clap_detector.dart`, `lib/input/squat_detector.dart`, `test/input/action_detector_test.dart`, `test/input/clap_detector_test.dart`, `test/input/squat_detector_test.dart`
- Modify: `test/helpers/synthetic_poses.dart` (let `makePose` take `kneeY` or a hip-drop so squat poses can be built)

**Interfaces:**
- Produces: `enum PuppyAction { jump, handsUp, clap, squat }`.
- Produces: `class ClapDetector { ClapDetector({Duration window = const Duration(milliseconds: 800), Duration debounce = const Duration(milliseconds: 800), double apartShoulderWidths = 1.0, double togetherShoulderWidths = 0.25, double maxDyTorso = 0.25, double minConfidence = Pose.minConfidence}); bool update(Pose p, Duration t); void reset(); }` — fires when both wrists were at least `apartShoulderWidths` × shoulder width apart (x distance) and, within `window`, come within `togetherShoulderWidths` with |dy| ≤ `maxDyTorso` × torso height and both wrists above the mid-hip y; shoulder width is measured from the current frame's shoulder x distance; a doubtful frame never fires; latched until the wrists are apart again.
- Produces: `class SquatDetector { SquatDetector(Calibration c, {double dropTorso = 0.25, Duration hold = const Duration(milliseconds: 300), double releaseTorso = 0.10, Duration grace = const Duration(milliseconds: 150)}); bool update(Pose p, Duration t); void reset(); }` — fires once when the mid-hip y is at least `dropTorso` × torso height below `calibration.baselineHipY` for `hold`; re-arms when it is back within `releaseTorso`; doubtful frames tolerated up to `grace`.
- Produces: `class ActionDetector { ActionDetector(Calibration c); Set<PuppyAction> update(Pose p, Duration t); void reset(); void suppressUntil(Duration t); void rebaseline(Pose p); }` composing `JumpDetector(c)`, `RaiseHandsDetector`, `ClapDetector`, `SquatDetector`; returns every action fired on this frame (usually empty); `suppressUntil`/`rebaseline` pass through to the jump detector and `suppressUntil` also blocks the other three.

- [ ] **Step 1: Write failing tests** with synthetic `Pose` maps (`makePose`, extended with a way to lower the hips/knees): clap — apart then together within the window fires once, a slow approach (> window) never fires, wrists below the hips never fire, a held clap does not re-fire until apart again, a doubtful frame never fires; squat — a drop of 0.3 torso held 300 ms fires once, 0.15 torso never fires, a dropout shorter than grace neither restarts nor double fires, standing back up re-arms; composite — each action alone yields exactly its own action; jump-with-hands-up yields both `jump` and `handsUp`; held hands-up across a long dropout fires once (latch); `suppressUntil` blocks all four.
- [ ] **Step 2: Run them, expect FAIL.**
- [ ] **Step 3: Implement the two detectors and `ActionDetector`.** Timing uses frame timestamps only; keep all numeric thresholds as named constructor defaults in one place (they are tuned in the device spike).
- [ ] **Step 4: Run all tests, expect PASS; `flutter analyze` clean. Commit** `feat(input): ActionDetector with clap and squat`.

### Task 2: ActionPerformed event and PoseSession flag

**Files:**
- Modify: `lib/input/game_input_event.dart`, `lib/input/pose_session.dart`, every exhaustive switch over `GameInputEvent` (`lib/modes/{catch_it,drag_spell,hold_pick,lane_jump,sky_shoot,yes_no}.dart`, plus tests with such switches), `test/input/pose_session_test.dart`

**Interfaces:**
- Produces: `class ActionPerformed extends GameInputEvent { const ActionPerformed(this.action, {required super.at}); final PuppyAction action; }`
- Produces: `PoseSession(..., bool actions = false)`; when true, `ActionDetector` runs on the smoothed pose and emits one `ActionPerformed` per returned action; it is reset exactly where `_raise`/`_handSide` are reset (failed frame, `player == null`, lost/found), `rebaseline` on found, and `suppressUntil` wherever `_jump.suppressUntil` is called. Knees stay unsmoothed unless a test shows lane/jump regressions are absent when they are added to `_smoothed`.

- [ ] **Step 1: Write failing session tests**: with `actions: true` a clap sequence emits `ActionPerformed(PuppyAction.clap)`; default `false` emits nothing; a held hands-up across PlayerLost/PlayerFound, failed frames and uncertain frames emits once; the reacquire grace blocks actions right after PlayerFound.
- [ ] **Step 2: Add the event, extend all exhaustive switches (ignored like `Pulled` by existing rounds), implement the flag, run tests PASS, analyze clean. Commit** `feat(input): ActionPerformed event`.

### Task 3: puppySays domain: config, question, round, gating

**Files:**
- Create: `assets/config/actions.json`, `lib/content/action_config.dart`, `lib/modes/action_round.dart`, `test/content/action_config_test.dart`, `test/modes/action_round_test.dart`
- Modify: `lib/content/models.dart` (`ModeKind.puppySays`), `lib/content/question_models.dart` (`QuestionForm.doAction`, `class ActionQuestion extends Question`), `lib/content/question_generator.dart`, `lib/levels/scoring.dart`, `lib/modes/mode_availability.dart`, `lib/progress/progress_store.dart`, `test/progress/progress_store_test.dart`, `test/content/content_validity_test.dart`, `test/ui/mode_picker_screen_test.dart` (the `hasLength(8)` pin) and every exhaustive switch over `ModeKind`/`QuestionForm`/`Question`

**Interfaces:**
- Produces: `assets/config/actions.json` — `{"actions":[{"id":"jump","command":"Jump!","ttsText":"Puppy says: jump!","hintVi":"Nhảy lên nào!","minGrade":1,"maxGrade":2}, ...]}` with the four actions (`jump`, `handsUp` "Hands up!", `clap` "Clap your hands!", `squat` "Squat down!"), all grades 1–2; `class ActionConfig { static const assetPath = 'assets/config/actions.json'; static Future<ActionConfig> load(AssetBundle b); List<ActionDef> forGrade(int grade); }` and `class ActionDef { String id, command, ttsText, hintVi; PuppyAction action; int minGrade, maxGrade; }` — strict `FormatException` on unknown action id, duplicate ids, empty strings, minGrade > maxGrade.
- Produces: `class ActionQuestion extends Question { ActionQuestion({required String itemId /* the action id */, required String ttsText, required this.command, required this.hintVi, required this.action}); form == QuestionForm.doAction }`.
- Produces: `class ActionRound implements Round { ActionRound(ActionQuestion q, {required Duration timeLimit}); }` — `ActionPerformed(a)` with `a == q.action` while `clockRunning` → `correct`; any other action is ignored; never `wrong`; timeout → `timeout`; lost/found as in `YesNoRound`; later events after the result are ignored.
- Produces: `QuestionGenerator` takes an optional `ActionConfig? actions`; a `{puppySays}` plan has exactly `questionCount` `ActionQuestion`s cycling through the grade's actions shuffled with the injected rng, no immediate repeat (when ≥ 2 actions), deterministic per seed; a plan that includes puppySays with no actions available is not produced (mode filtered out); the other modes' rng streams and plans are unchanged.
- Produces: `Scoring.timeFor(level, ModeKind.puppySays)` = base × 2; `kModeInfos` entry `ModeInfo(mode: ModeKind.puppySays, title: 'Theo Pup', minGrade: 1, maxGrade: 2, usesCamera: true)`; `ProgressStore.puppySaysEnabled` (key `progress.puppySays`, bool, default false, corrupt → false) and `Future<void> setPuppySaysEnabled(bool)`.
- Content-validity loops that iterate `modesForGrade` must skip puppySays (it is not item-based).

- [ ] **Step 1: Write failing tests**: config parsing (valid, unknown action, duplicate id, empty string, bad grade range), round contract (correct on matching action, ignores other actions, never wrong, timeout, lost/found, ignores events after the result and before start), generator (exact `questionCount` for grades 1–2 × levels, cycling, no immediate repeat, determinism, no puppySays plan without actions), store flag (default false, persisted, corrupt reads false), availability table for grades 1–5, `Scoring`.
- [ ] **Step 2: Implement** and fix every exhaustive switch (`flutter analyze`); `PlayScreen` keeps its `_ =>` fallback until Task 5 — add an explicit `StateError`-free placeholder only if analyze demands it.
- [ ] **Step 3: Run all tests, analyze clean, commit** `feat(modes): puppySays domain, actions config and flag`.

### Task 4: Controller wiring and gating

**Files:**
- Modify: `lib/app/game_controller.dart`, `lib/app/app.dart` (load `ActionConfig` with a try/catch; failure → no actions, mode unavailable), `test/helpers/game_harness.dart`
- Test: `test/app/puppy_says_flow_test.dart`

**Interfaces:**
- Consumes: `ActionRound`, `ActionPerformed`, `PoseSession(actions:)`, `ActionConfig`, `ProgressStore.puppySaysEnabled`.
- Produces: `GameController(..., ActionConfig? actions)`; `activeModes` drops puppySays unless `actions != null && store.puppySaysEnabled`; the shuffle set (`modesForGrade` minus sayIt) also drops puppySays when disabled; `_makeRound` builds `ActionRound` for `ModeKind.puppySays`; `PoseSession(actions: activeModes.contains(ModeKind.puppySays))`; the PlayerLost-at-round-start condition includes `ActionRound`; the spoken prompt is `ttsText` with no word-clip lookup (`_clipId` null for `doAction`); post-answer explanation: correct → nothing extra; timeout → opening line `outOfTime`, then the Vietnamese hint line via the existing caption path (no "wrong" line).

- [ ] **Step 1: Write failing flow tests** (`debugInject(ActionPerformed(...))`, then a real clap pose sequence through `PoseSession`): correct action answers; other action ignored; no action → neutral timeout with the hint caption and never wrong; child absent at round start waits and resumes; flag off + `mode: puppySays` falls back to the default mix; flag off excludes it from shuffle; flag on includes it for grades 1–2 only; the lane tracker is not touched for puppySays.
- [ ] **Step 2: Implement; run the full suite, analyze clean. Commit** `feat(controller): wire puppySays behind a parent flag`.

### Task 5: PuppySaysScreen, picker, parent toggle, docs

**Files:**
- Create: `lib/ui/screens/puppy_says_screen.dart`, `test/ui/puppy_says_screen_test.dart`, `docs/device-spike-actions.md`
- Modify: `lib/ui/screens/play_screen.dart`, `lib/ui/screens/mode_picker_screen.dart` (`puppySaysAvailable` parameter like `sayItAvailable`), `lib/ui/parent/parent_settings.dart` (switch `ValueKey('toggle-puppysays')`), `lib/app/app.dart` (pass availability), `test/ui/parent_test.dart`, `test/ui/mode_picker_screen_test.dart`, `docs/known-limitations.md`

**Interfaces:**
- Produces: `PuppySaysScreen({required GameController controller, VoidCallback? onExit})` routed from `PlayScreen` for `ModeKind.puppySays`: the Space Puppy mascot large, the command in a prompt pill (36 sp+ play style), an action pictogram (Material icons only), a countdown ring/bar from `hudTick`, a verdict via `RoundVerdict` (correct "Giỏi lắm!"; timeout "Hết giờ" with the Vietnamese hint line, never "Sai"), reduce-motion respected; no camera image anywhere; no touch answer.
- Produces: parent switch "Trò Theo Pup (thử nghiệm)" with a one-line explanation that it is experimental; picker shows the tile only when available.
- Produces: `docs/device-spike-actions.md`: step-by-step how the owner tests on a phone (what to do, what to count: misses and false detections per action, where to tune each named threshold constant) and the go/no-go bar (e.g. ≥ 90 % detection for jump and hands up, ≥ 80 % for clap and squat, < 1 false trigger per minute standing still), before enabling by default.
- Known-limitations additions: puppySays is experimental and off by default; thresholds unverified on a device; no skeleton overlay (spec §2 calls for joints only; not built); no touch fallback; knees are not smoothed.

- [ ] **Step 1: Write failing widget tests** at 800×360 and 1280×720 with `textScaler` 1.3: no overflow; command ≥ 28 sp; mascot, pictogram, ring present; timeout shows "Hết giờ" and the hint and never "Sai"; correct shows "Giỏi lắm!"; routing from `PlayScreen`; picker hides/shows the tile with the flag; parent toggle persists and defaults off.
- [ ] **Step 2: Implement with AppTheme tokens only; run the full suite, analyze clean. Commit** `feat(ui): puppySays screen, picker tile and parent switch`.

### Task 6: Release hardening

**Files:**
- Create: `android/app/proguard-rules.pro`, `docs/release.md`
- Modify: `android/app/build.gradle.kts`, `.github/workflows/ci.yml`, `test/platform/android_build_test.dart`, `docs/android-build-notes.md`

**Interfaces:**
- Produces: in `android/app/build.gradle.kts`: read `android/key.properties` (keys `storeFile`, `storePassword`, `keyAlias`, `keyPassword`) when it exists and define `signingConfigs.release` from it; `buildTypes.release` uses `signingConfigs.release` when `key.properties` exists, otherwise the debug config (so CI and contributors can still build) and prints a warning; `isMinifyEnabled = true`, `isShrinkResources = true`, `proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")`.
- Produces: `proguard-rules.pro` with keep/dontwarn rules for `com.google.mediapipe.**`, `com.google.protobuf.**` and anything the plugins need (start from `-keep class com.google.mediapipe.** { *; }` and `-dontwarn` rules, extend using R8's `missing_rules.txt` from the CI build output if the release job reports missing classes).
- Produces: CI job `build-android-release` (same setup as `build-android`) running `flutter build apk --release` and uploading the APK as an artifact; `docs/release.md` with keystore creation (`keytool` command), `key.properties` format, "never commit it", and the Families/ads decision still being the owner's.

- [ ] **Step 1: Extend `test/platform/android_build_test.dart`** to pin: `key.properties` is read, `isMinifyEnabled = true`, `proguard-rules.pro` exists and keeps `com.google.mediapipe`, no keystore or password literal in the repo, `.gitignore` covers `key.properties` and `*.jks`; run, expect FAIL.
- [ ] **Step 2: Implement the Gradle, proguard, CI and docs changes**; run the platform tests and the full suite. Gradle cannot run locally (no Android SDK): the new CI job is the verification, so report that it still has to go green; commit `build(android): R8 rules, release signing from key.properties, CI release job`.
