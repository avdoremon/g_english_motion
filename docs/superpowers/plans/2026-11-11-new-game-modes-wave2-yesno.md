# Wave 2: HandSideDetector + yesNo "Đúng/Sai" Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the `yesNo` mode: a picture and a statement; the child raises the LEFT hand for Đúng or the RIGHT hand for Sai (touch fallback), for grades 1–5.

**Architecture:** A per-hand `HandSideDetector` in `lib/input` feeds a new `HandRaised(hand)` event through `PoseSession`. A new `YesNoRound` (Round contract) maps it to choice 0/1 of a two-choice `ChoiceQuestion` of the new form `trueFalse`. Generator, tag tool, availability table, controller and one new screen are extended exactly the way Wave 1 added `catchIt`.

**Tech Stack:** Flutter 3.47/Dart, existing pose pipeline, `tools/tag_modes.py`.

**Spec:** `docs/superpowers/specs/2026-11-07-new-game-modes-design.md` (§2 yesNo, §3.3 HandSideDetector, §3.5, §7). Wave 1 plan `docs/superpowers/plans/2026-11-07-new-game-modes-wave1.md` is the model for structure and review gates.

## Global Constraints

- Round contract (`lib/modes/round.dart`): events before tick; clock stops while the player is lost; result set once; zero/negative tick ignored; oversize tick clamps and ends with `RoundResult.timeout` (neutral "Hết giờ").
- Uncertain input is never graded wrong: both hands up, a doubtful frame, or the player lost produce no answer.
- The answer never leaks: nothing before the answer (caption, Semantics, TTS, picture) says whether the statement is true. The statement itself is the question and is shown and spoken.
- Touch targets ≥ 56 dp; play text ≥ 28 sp (Label 24 sp only for counters/HUD chips); no overflow at 800×360 and 1280×720 including `textScaler` 1.3; Wave 0 lint (`test/ui/no_hardcoded_style_test.dart`): only font sizes {56,48,36,28,24}, no `Color(`/`Colors.white|black` outside `app_theme.dart` and `*_painter.dart`.
- No network libraries; level table, star thresholds, `questionCount` unchanged; progress keyed by (grade, level); the default "Chơi" mix unchanged.
- Selfie mirroring decided in ONE place: `HandSideDetector` reads the anatomical `leftWrist`/`rightWrist` joints (the pose plugin labels by the person's own side); a single `swapSides` constructor flag (default false) exists for the device spike. Screen shows Đúng on the left, Sai on the right.
- Flutter is installed in CI only if not available locally; run `flutter analyze` and `flutter test` when the tools exist, otherwise rely on CI. Never run `dart format` on the whole repo.

## Review Focus

- Both hands raised (or one hand raised while the other wrist is unreliable) produces no `HandRaised` and no answer. Test in Task 1.
- A one-frame landmark dropout neither restarts the hold nor fires twice. Test in Task 1.
- The child absent when the round starts (LevelSession drops `PlayerLost` outside `playing`): the round waits, no neutral timeout burns and nothing is graded. Test in Task 3.
- False statements never contain the shown item's word, and "a"/"an" is grammatical after the word swap (`an apple`, `a dog`). Items without a usable sentence pattern still produce a statement. Test in Task 2.
- Every grade × unit × level yields exactly `questionCount` yesNo questions, balanced true/false (the counts differ by at most 1), and the picker with 9 tiles has no overflow at 800×360 / 1280×720. Tests in Tasks 2 and 4.

---

### Task 1: HandSideDetector, HandRaised, PoseSession flag

**Files:**
- Create: `lib/input/hand_side_detector.dart`, `test/input/hand_side_detector_test.dart`
- Modify: `lib/input/game_input_event.dart`, `lib/input/pose_session.dart`, every exhaustive `switch` over `GameInputEvent` (find with `flutter analyze`; at least `lib/modes/*.dart`), `test/input/pose_session_test.dart` (or the existing session test file)

**Interfaces:**
- Produces: `class HandRaised extends GameInputEvent { const HandRaised(this.hand, {required super.at}); final Hand hand; }`
- Produces: `class HandSideDetector { HandSideDetector({Duration hold = const Duration(milliseconds: 500), double minConfidence = Pose.minConfidence, Duration grace = const Duration(milliseconds: 150), bool swapSides = false}); Hand? update(Pose p, Duration t); void reset(); }` — `update` returns the hand exactly once per raise.
- Produces: `PoseSession(..., bool handSide = false)`; when true it emits `HandRaised` and resets the detector exactly where `_raise` is reset today (player lost/found, failed frame).

- [ ] **Step 1: Write failing detector tests** (synthetic `Pose` maps as in `test/input/raise_hands_detector_test.dart`): left alone above nose 500 ms → `Hand.left` once, none while it stays up; lower then raise again → fires again; right alone → `Hand.right`; both up 1 s → null throughout; both up, right lowers, left stays → left fires 500 ms after it became alone; one-frame nose/wrist dropout (< grace) during the hold neither restarts nor double fires, a dropout longer than grace restarts the hold; a frame where the other wrist is unreliable never fires; `swapSides: true` turns a left raise into `Hand.right`; timing uses frame timestamps only.
- [ ] **Step 2: Run them, expect FAIL** (`flutter test test/input/hand_side_detector_test.dart`).
- [ ] **Step 3: Implement `HandSideDetector`** by mirroring `RaiseHandsDetector` (per-hand `_since/_lastRaised/_fired/_doubt`). A hand counts as raised-alone only when its wrist is above the nose and the other wrist is reliably NOT above the nose.
- [ ] **Step 4: Add `HandRaised` and extend all exhaustive switches** (treat like `Pulled`: ignored by rounds that do not use it) so `flutter analyze` is clean.
- [ ] **Step 5: Write failing session test**: with `handSide: true` a left-hand-raise frame sequence emits `HandRaised(Hand.left)`; with the default `false` nothing is emitted; after `PlayerLost`/`PlayerFound` the hold restarts.
- [ ] **Step 6: Implement the `PoseSession` flag**, run the tests, expect PASS.
- [ ] **Step 7: Commit** `feat(input): HandSideDetector and HandRaised event`.

### Task 2: yesNo domain: round, question form, generator, tags

**Files:**
- Create: `lib/modes/yes_no.dart`, `test/modes/yes_no_round_test.dart`
- Modify: `lib/content/models.dart` (`ModeKind.yesNo`), `lib/content/question_models.dart` (`QuestionForm.trueFalse`), `lib/content/question_generator.dart`, `lib/levels/scoring.dart`, `lib/modes/mode_availability.dart`, `tools/tag_modes.py`, `test/tools/test_tag_modes.py`, `test/content/content_validity_test.dart` and the generator sweep tests, `test/modes/mode_availability_test.dart`, `assets/content/**/*.json` (run the tag tool)

**Interfaces:**
- Consumes: `HandRaised`, `Round`, `ChoiceQuestion`.
- Produces: `class YesNoRound implements Round { YesNoRound(ChoiceQuestion question, {required Duration timeLimit}); void answer(int index); }` — choice 0 = Đúng (left hand), 1 = Sai (right hand). `HandRaised(left)` → `answer(0)`, `HandRaised(right)` → `answer(1)`; ignored before `start`, while the player is lost, and after a result. `answer` is also the touch fallback with the same gating. A wrong or right answer sets the result once; no answer by the time limit ends as `timeout`.
- Produces: generated `ChoiceQuestion`: `form: trueFalse`, `choices` = two `ChoiceOption(itemId: item.id, showPicture: false, showWord: false)`, `promptImageItemId: item.id`, `promptText` = the statement, `ttsText` = the statement, `correctIndex` 0 when the statement is true else 1.
- Produces: `Scoring.timeFor(level, ModeKind.yesNo)` = base; `kModeInfos` entry `ModeInfo(mode: ModeKind.yesNo, title: 'Đúng/Sai', minGrade: 1, maxGrade: 5, usesCamera: true)`; `defaultModesForGrade` unchanged.

- [ ] **Step 1: Write failing round tests**: left → correct when `correctIndex == 0`, wrong when 1; right likewise; events before `start` and while lost are ignored; `answer` honours the same gates; tick past the limit with no answer → `timeout`; zero tick ignored; oversize tick clamps; result never changes after set; clock stops while lost and resumes on `PlayerFound`.
- [ ] **Step 2: Implement `YesNoRound`**, tests PASS.
- [ ] **Step 3: Add the enum values and the wiring** in `_modeForms` (`ModeKind.yesNo: [QuestionForm.trueFalse]`), `Scoring`, `kModeInfos`; fix every exhaustive switch over `ModeKind`/`QuestionForm`.
- [ ] **Step 4: Write failing generator tests** (use the existing sweep helpers): for every grade 1–5 × unit × level, a `{yesNo}` plan has exactly `questionCount` questions, all `trueFalse` with two choices; across the plan the number of true statements differs from the false ones by at most 1 (shuffle a balanced boolean list with the injected rng, deterministic per seed); a true statement contains the item's word; a false statement contains a distractor's word and NOT the item's word; "a"/"an" agrees with the next word (`a dog`, `an apple`); an item with no usable `sentencePatterns` falls back to the bare claimed word as statement and tts; `promptImageItemId == itemId`; the widened-pool rule (no item more than twice) still holds.
- [ ] **Step 5: Implement the generator branch**: statement from the first sentence pattern containing the item word (reuse `_wordRe`), word replaced by the claimed word (item or a distractor with a word), then fix `a`/`an`; the false claim picks a distractor from `distractorIds` (valid ids only).
- [ ] **Step 6: Tag tool**: `yesNo` = item has an image and ≥ 1 valid distractor id that exists. Add the python tests (tagged, idempotent, never removes a tag), run `python3 tools/tag_modes.py`, then `--check` exits 0 and `python3 -m unittest discover -s test/tools` passes. Extend `content_validity_test.dart`: every `yesNo`-tagged item has an image and a valid distractor.
- [ ] **Step 7: Pin the availability table** for grades 1–5 including `yesNo`; run all tests, analyze clean.
- [ ] **Step 8: Commit** `feat(modes): yesNo round, trueFalse questions and tags`.

### Task 3: Controller wiring

**Files:**
- Modify: `lib/app/game_controller.dart`, `test/helpers/game_harness.dart` if needed
- Test: `test/app/yes_no_flow_test.dart`

**Interfaces:**
- Consumes: `YesNoRound`, `HandRaised`, `PoseSession(handSide:)`.
- Produces: `GameController.answerYesNo(int index)` (touch fallback: calls `YesNoRound.answer` through `_session?.act`, then `_afterSessionChange` and `notifyListeners`, like `holdTarget`).

- [ ] **Step 1: Write failing flow tests**: with `activeModes == {yesNo}`: a left `HandRaised` injected with `debugInject` while playing answers choice 0; tap fallback `answerYesNo(1)` answers choice 1; the prompt speaks `ttsText`; a `HandRaised` during the prompt is ignored; the child absent at round start (player lost during the prompt) → after the prompt the clock does not run, nothing is graded, `PlayerFound` resumes it; mixed shuffle at grade 1 `{laneJump, catchIt, yesNo}` plays all three without stale lane or event leaks (lane count only touched for lane modes).
- [ ] **Step 2: Implement**: `_makeRound` case `ModeKind.yesNo`; `PoseSession(handSide: activeModes.contains(ModeKind.yesNo))`; extend the PlayerLost-at-round-start condition with `YesNoRound`; `trueFalse` must NOT be in `_hidesWord` (the statement is shown); `answerYesNo`.
- [ ] **Step 3: Run the whole suite, analyze clean. Commit** `feat(controller): wire yesNo`.

### Task 4: YesNoScreen, routing, picker, docs

**Files:**
- Create: `lib/ui/screens/yes_no_screen.dart`, `test/ui/yes_no_screen_test.dart`
- Modify: `lib/ui/screens/play_screen.dart`, `lib/ui/screens/mode_picker_screen.dart`, `docs/known-limitations.md`, picker/mode tests

**Interfaces:**
- Consumes: `GameController` (`session`, `itemFor`, `hudTick`, `answerYesNo`), kit widgets (`PlayHeader`, `StickerCard`, `BigButton`), `ItemPicture`; model the file on `catch_it_screen.dart` and `lane_jump_screen.dart`.
- Produces: `YesNoScreen({required GameController controller, required VoidCallback onExit})` routed from `PlayScreen` for `ModeKind.yesNo`.

- [ ] **Step 1: Write failing widget tests** at 800×360 and 1280×720, also with `textScaler` 1.3: no overflow; the picture, the statement (≥ 28 sp style) and two answer targets (≥ 56 dp) are present, "Đúng" on the left and "Sai" on the right; tapping a side calls `answerYesNo(0|1)`; Semantics before the answer never say whether the statement is true; after the answer a result line appears; reduce-motion respected; picker shows 9 tiles at grade 3+ without overflow.
- [ ] **Step 2: Implement the screen** with AppTheme tokens only (no colour/font-size literals), route it in `PlayScreen`, give the picker tile an icon (`Icons.back_hand`, the default) and keep tile titles at 28 sp.
- [ ] **Step 3: Docs**: in `docs/known-limitations.md` add: hand sides rely on the plugin labelling the person's own side (verify on a device; `swapSides` is the switch); a yesNo question is guessable at 50 % and the level's `questionCount` is unchanged; false statements use the item's distractors.
- [ ] **Step 4: Run the whole suite, analyze clean, `tag_modes.py --check`. Commit** `feat(ui): yesNo screen and routing`.
