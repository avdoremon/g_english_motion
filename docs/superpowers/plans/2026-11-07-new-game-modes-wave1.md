# New Game Modes — Wave 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the mode framework, a mode picker on Home, and three new camera modes — `catchIt` (Hứng hình), `memoryFlip` (Lật thẻ), `balloonPop` (Chọc bóng).

**Architecture:** Extend `ModeKind`/`QuestionForm`, drive per-grade availability from one constant table shared by the picker and `GameController._modes`, reuse `ChoiceQuestion` for all three modes, add `CatchItRound` (lane input, composition over `LaneJumpRound`) and `HoldPickRound` (hold-to-pick via `HoldTracker`, tap fallback through `GameController.holdTarget`), tag content with an idempotent tool. Waves 2 (`HandSideDetector` + `yesNo`) and 3 (`ActionDetector` + `puppySays`, after the device spike) are separate plans and only add enum values, tiles and rounds.

**Tech Stack:** Flutter 3.47.9, Dart, existing MediaPipe pose pipeline, Python 3 for `tools/tag_modes.py`.

**Spec:** `docs/superpowers/specs/2026-11-07-new-game-modes-design.md` (§2–§5, §7). Visual reference: design canvas boards Modes, CatchIt, MemoryFlip, BalloonPop. Depends on Wave 0 (`docs/superpowers/plans/2026-11-07-ui-kit-space-puppy.md`) for `StickerCard`, `BigButton`, `HudBar`, `TinTin`; if Wave 0 is not merged, build on the current widgets and re-skin later.

## Global Constraints

- Uncertain input is never graded wrong: no event ⇒ no grade; timeout ends neutrally with "Hết giờ".
- The answer never leaks: caption, `Semantics` labels, TTS and picture reveal nothing about the correct choice before the answer (tests assert absence).
- Round contract (from `lib/modes/round.dart`): within a frame `onEvent` before `tick`; clock stops after `PlayerLost` until `PlayerFound`; `result` is set once; zero/negative tick ignored; oversize tick clamps to timeout.
- Touch targets ≥ 56 dp; play text ≥ 28 sp; no overflow at 800×360 and 1280×720.
- Star thresholds, level table, ProgressStore keying by (grade, level) unchanged; any mode counts towards the same level.
- No new packages; architecture test (no network libs) and release manifest (no INTERNET) still pass.
- Grades: catchIt 1–2, memoryFlip 2–5, balloonPop 3–5. "Chơi" on Home keeps today's per-grade mix (laneJump for 1–2; dragSpell + skyShoot for 3–5); new modes are reachable only through the picker.
- Hold times: memoryFlip 1 s, balloonPop 0.6 s, grace 200 ms (the `HoldTracker` default); peek time 2 s.
- Touch fallback: memoryFlip and balloonPop keep tap; catchIt has none (like LaneJump); record in `docs/known-limitations.md`.

## Review Focus

- Child sweeps the hand across balloons/cards without pausing: nothing pops/flips (hold, not touch).
- Hand leaves frame mid-hold or `PlayerLost` fires: progress resets, clock stops, no wrong answer.
- Two cards/balloons overlap the cursor at once: only the nearest-centre target accumulates hold.
- A grade with no item tagged for the chosen mode (e.g. unit with no images): generator falls back or the picker tile is disabled with a message; never an empty or crashing session.
- Picker "Trộn ngẫu nhiên" with a grade that has only one valid mode still starts.
- Content tagging run twice: second run changes nothing; running it never removes existing tags.

---

### Task 1: Mode enum, forms, availability table

**Files:**
- Modify: `lib/content/models.dart:1`, `lib/content/question_models.dart:3`, `lib/content/question_generator.dart:10`, `lib/app/game_controller.dart:127`
- Create: `lib/modes/mode_availability.dart`
- Test: `test/modes/mode_availability_test.dart`

**Interfaces:**
- Produces: `ModeKind` gains `catchIt, memoryFlip, balloonPop`; `QuestionForm` gains `memoryMatch, popWord`; `class ModeInfo { final ModeKind mode; final String title; final int minGrade, maxGrade; final bool usesCamera; }`; `const List<ModeInfo> kModeInfos`; `Set<ModeKind> modesForGrade(int grade)` = every mode with `minGrade ≤ grade ≤ maxGrade`; `Set<ModeKind> defaultModesForGrade(int grade)` = today's mix (`{laneJump}` for ≤2, `{dragSpell, skyShoot}` for ≥3). `sayIt` is listed in `kModeInfos` (grades 1–5) but is not in either set functions' defaults.
- `_modeForms`: `catchIt: [listenPickPicture]`, `memoryFlip: [memoryMatch]`, `balloonPop: [popWord]`.
- `GameController` gains optional `ModeKind? mode`; `_modes` = `{mode}` when given and valid for the grade, else `defaultModesForGrade(grade)`.

- [ ] **Step 1: Failing tests** — `modesForGrade(1)` contains `catchIt, laneJump` not `balloonPop`; `modesForGrade(3)` contains `balloonPop, memoryFlip, dragSpell, skyShoot` not `catchIt`; `defaultModesForGrade(2)=={laneJump}` and `(4)=={dragSpell, skyShoot}`; `GameController(grade:4, mode: ModeKind.catchIt)` ignores the invalid mode and falls back to the default set (use `test/helpers/game_harness.dart`).
- [ ] **Step 2: Run** `flutter test test/modes/mode_availability_test.dart` — FAIL (symbols missing).
- [ ] **Step 3: Implement** the enum/form additions and the table; make every `switch` over `ModeKind`/`QuestionForm` exhaustive (`flutter analyze` lists them; new cases may `throw UnimplementedError` only until Tasks 3–5).
- [ ] **Step 4: Run** `flutter analyze && flutter test` — green (existing behaviour unchanged).
- [ ] **Step 5: Commit** `feat(modes): mode kinds, forms, availability table`.

### Task 2: Content tagging tool and generator forms

**Files:**
- Create: `tools/tag_modes.py`, `test/tools/tag_modes_test.py` (run by `python3 -m unittest`), CI step in `.github/workflows/*.yml` running `python3 tools/tag_modes.py --check`
- Modify: `assets/content/grade*/u*.json` (by the tool), `lib/content/question_generator.dart` (build forms), `test/content/content_validity_test.dart`
- Test: `test/content/question_generator_modes_test.dart`

**Interfaces:**
- Consumes: item JSON shape (`id`, `modes`, `image`, `distractorIds`, `word` — read one unit file first and use its real field names).
- Produces: `tag_modes.py [--check]` — adds `memoryFlip` and `catchIt` to items with an image and ≥ 2 distractors; adds `balloonPop` to items with ≥ 2 other words in the same grade pool at edit distance ≤ 2 (case-insensitive, whole-grade pool); never removes a tag; `--check` exits 1 if a write would change anything. Generator builds `ChoiceQuestion` with `form: memoryMatch` (`promptImageItemId` = target, 3–5 word choices, `ttsText` = target word), `popWord` (prompt picture, 3–5 balloons ≤ 2 edit distance); `catchIt` reuses the existing `listenPickPicture` builder (3 pictures, 3 lanes).

- [ ] **Step 1: Failing tests:** (python) running `tag_modes` on a fixture twice yields identical files; a fixture item with no image gets no `memoryFlip`; edit-distance helper `lev('cat','cap')==1`. (dart) with a grade-3 content fixture and `modes:{balloonPop}`, `plan(...)` yields `ChoiceQuestion`s with `form==popWord`, 3–5 choices, every choice differs from the answer by edit distance ≤ 2, `correctIndex` valid, no duplicate words; `memoryMatch` has `promptImageItemId==itemId`; `catchIt` questions have exactly 3 picture choices (three lanes, as the spec's "three pictures fall in three lanes"). `content_validity_test`: every item tagged `balloonPop` has ≥ 2 usable distractors; every unit still fills a level for each grade-valid mode.
- [ ] **Step 2: Run** python unittest and `flutter test test/content` — FAIL.
- [ ] **Step 3: Implement** the tool, run it once over `assets/content`, and add generator support in `_modeForms` consumers: `memoryMatch`/`popWord` choice building reuses the existing distractor selection with the edit-distance filter for `popWord`. `catchIt` uses the existing `listenPickPicture` builder unchanged (3 choices).
- [ ] **Step 4: Run** `python3 tools/tag_modes.py --check` (exit 0), `flutter test` — green.
- [ ] **Step 5: Commit** `feat(content): tag new modes, generate memory/pop questions`.

### Task 3: CatchItRound

**Files:**
- Create: `lib/modes/catch_it.dart`
- Modify: `lib/app/game_controller.dart` (`_makeRound` case `ModeKind.catchIt`), `lib/modes/lane_jump.dart` only if its constructor cannot be composed as-is
- Test: `test/modes/catch_it_test.dart`

**Interfaces:**
- Consumes: `ChoiceQuestion`, `Round`, `LaneChanged(lane)`, `Confirmed(lane)`, `LaneJumpRound` (read `lib/modes/lane_jump.dart` to decide: compose it, or copy its lane logic if the falling clock differs).
- Produces: `class CatchItRound implements Round { CatchItRound(ChoiceQuestion q, {required Duration timeLimit, required int initialLane}); int get lane; double get fallFraction; }` — `fallFraction == elapsedFraction`; at timeLimit the round resolves to `correct` if `lane == q.correctIndex` else `wrong` (never `timeout`; the catch line IS the answer). `Confirmed` is ignored (no early answer). While the player is lost the clock and `fallFraction` freeze.

- [ ] **Step 1: Failing tests:** lane at the catch line equals correct → `correct`; wrong lane → `wrong`; `LaneChanged` after the catch line is ignored; events-before-tick ordering (lane change in the last frame counts); `PlayerLost` freezes `fallFraction` and `PlayerFound` resumes; result never changes after set; tick of zero ignored.
- [ ] **Step 2: Run** `flutter test test/modes/catch_it_test.dart` — FAIL.
- [ ] **Step 3: Implement** per the interface; wire `_makeRound`.
- [ ] **Step 4: Run** the test and `flutter test` — PASS.
- [ ] **Step 5: Commit** `feat(modes): catchIt round`.

### Task 4: HoldPickRound and tap fallback

**Files:**
- Create: `lib/modes/hold_pick.dart`
- Modify: `lib/app/game_controller.dart` (`_makeRound` cases `memoryFlip`, `balloonPop`; `holdTarget` handles `choice:<i>`)
- Test: `test/modes/hold_pick_test.dart`, `test/app/game_controller_hold_test.dart`

**Interfaces:**
- Consumes: `HoldTracker`, `CursorMoved(x,y)`, `ChoiceQuestion`, `Round`.
- Produces: `class HoldPickRound implements Round { HoldPickRound(ChoiceQuestion q, {required Duration timeLimit, required Duration holdTime, Duration peek = Duration.zero, required Rect Function(int choice) targetRect}); String? get hoverTarget; double get holdProgress; bool get peeking; void onTargetHeld(String targetId); }` — `targetRect` gives the normalised (0..1) rect of choice `i` so the round can map the cursor to `choice:<i>` (nearest centre if overlapping); during `peek` the clock and cursor are inert (cards face-up); a completed hold or `onTargetHeld('choice:<i>')` sets `chosenIndex=i` and `result` correct/wrong exactly once. memoryFlip uses `holdTime: 1 s, peek: 2 s`; balloonPop `0.6 s`, no peek. `GameController.holdTarget(id)` routes `choice:` ids to `HoldPickRound.onTargetHeld`.

- [ ] **Step 1: Failing tests:** cursor sweeping across three targets at 100 ms per target never completes a hold; hold 1.0 s on target 1 ⇒ `chosenIndex==1`; leaving for < 200 ms keeps progress, ≥ 200 ms resets; overlapping rects pick the nearest centre; during `peek` a long hold does nothing and the clock does not run; `PlayerLost` mid-hold resets progress and freezes the clock; timeout ⇒ `RoundResult.timeout`; `onTargetHeld('choice:2')` grades as a tap; a second pick after result is ignored.
- [ ] **Step 2: Run** the two test files — FAIL.
- [ ] **Step 3: Implement** with one `HoldTracker(holdTime: holdTime)` fed `choice:<i>` ids and frame timestamps (never wall-clock); wire the controller.
- [ ] **Step 4: Run** `flutter test` — PASS.
- [ ] **Step 5: Commit** `feat(modes): hold-to-pick round for memoryFlip and balloonPop`.

### Task 5: Screens for the three modes

**Files:**
- Create: `lib/ui/screens/catch_it_screen.dart`, `memory_flip_screen.dart`, `balloon_pop_screen.dart`, `lib/ui/shell/hold_ring.dart`
- Modify: `lib/ui/screens/play_screen.dart:28` (route new `ModeKind`s)
- Test: `test/ui/catch_it_screen_test.dart`, `memory_flip_screen_test.dart`, `balloon_pop_screen_test.dart`

**Interfaces:**
- Consumes: `GameController`, `CatchItRound`/`HoldPickRound` getters above, `PlayHeader`, existing prompt-pill/caption/verdict widgets (`round_verdict.dart`), `PlaySurface`.
- Produces: `HoldRing({required double progress, double size = 56})` painted ring around the hand cursor; each screen follows the canvas boards (catchIt: three falling stickers + Puppy under the chosen lane; memoryFlip: face-up target + 3–5 cards that flip after peek; balloonPop: picture prompt + balloons with words).

- [ ] **Step 1: Failing tests (each screen, sizes 800×360 and 1280×720):** no overflow; all play text ≥ 28 sp; tap targets (cards/balloons) ≥ 56 dp; tapping a card/balloon calls `holdTarget('choice:<i>')`; `Semantics` tree and caption contain none of the correct word before the result (memoryFlip: the target picture's word is the answer and must not appear); catchIt screen has no tappable choices.
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** the screens and `HoldRing`; keep captions to one line; reduce-motion: fall/flip animations replaced by instant state changes.
- [ ] **Step 4: Run** `flutter analyze && flutter test` — green.
- [ ] **Step 5: Commit** `feat(ui): catchIt, memoryFlip, balloonPop screens`.

### Task 6: ModePickerScreen and Home entry

**Files:**
- Create: `lib/ui/screens/mode_picker_screen.dart`
- Modify: `lib/ui/screens/home_screen.dart`, `lib/app/` navigation (where Home starts a session), `docs/known-limitations.md`
- Test: `test/ui/mode_picker_screen_test.dart`, update `test/ui/home_screen_test.dart`

**Interfaces:**
- Consumes: `kModeInfos`, `modesForGrade`, `GameController(mode:)`.
- Produces: `ModePickerScreen({required int grade, required void Function(ModeKind? mode) onPick})` — `mode == null` means "Trộn ngẫu nhiên" (all valid modes for the grade, via `modesForGrade`); tiles show title, grade range, input icon; tiles not valid for the grade are shown disabled with the grade range as the reason. Home gets a "Chọn trò chơi" button next to "Chơi"; "Chơi" keeps `defaultModesForGrade`.

- [ ] **Step 1: Failing tests:** grade 1 enables laneJump and catchIt and disables balloonPop; grade 4 enables dragSpell, skyShoot, memoryFlip, balloonPop; tapping an enabled tile calls `onPick(mode)`; "Trộn ngẫu nhiên" calls `onPick(null)`; disabled tile does nothing; no overflow at both sizes and at textScaler 1.3; Home "Chơi" still starts with the default mix (existing test).
- [ ] **Step 2: Run** — FAIL.
- [ ] **Step 3: Implement** the picker from the kit, wire Home; document touch-fallback and picker behaviour in `docs/known-limitations.md`.
- [ ] **Step 4: Run** `flutter analyze && flutter test`, then `flutter build apk --debug` — all succeed.
- [ ] **Step 5: Commit** `feat(ui): mode picker`.
