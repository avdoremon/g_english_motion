# New game modes and mode picker — design

Status: draft for review. Date: 2026-11-07. Base: `main` (`153fe8e`).

## 1. Purpose and success criteria

Tin Tin English has four ways to play (LaneJump, DragSpell, SkyShoot, SayIt).
The owner wants **more activities a child can choose from**, so a session
does not feel repetitive. Decision taken: add **5 camera-controlled modes** that
reuse the existing vocabulary, plus a **mode picker** on the home screen.

Success:

1. A child can pick a mode from a picker (9 tiles + "Trộn ngẫu nhiên") or just
   press "Chơi" as today.
2. Every new mode obeys the existing rules: uncertain input is never graded
   wrong; the answer never leaks (caption, TalkBack label, TTS, picture); no
   network; touch targets ≥ 56 dp; play text ≥ 28 sp; no overflow at 800×360
   and 1280×720; star thresholds and the level table are unchanged.
3. Existing modes, progress data and content keep working unchanged.

Not in scope: a new art style (see §8, sequencing), ads, new grades.

Visual reference: the canvas "Tin Tin English — thiết kế lại giao diện game",
row "Chọn trò chơi và 5 trò mới".

## 2. The five modes

| Mode (`ModeKind`) | Question form | Input | Grades |
|---|---|---|---|
| `catchIt` "Hứng hình" | `listenPickPicture` (existing) | body left/right (`LaneChanged`) | 1–2 |
| `memoryFlip` "Lật thẻ" | `memoryMatch` (new) | hand cursor + hold (`CursorMoved`, tap fallback) | 2–5 |
| `balloonPop` "Chọc bóng" | `popWord` (new) | hand cursor + hold (tap fallback) | 3–5 |
| `yesNo` "Đúng/Sai" | `trueFalse` (new) | left or right hand raised (`HandRaised`, new) | 1–5 |
| `puppySays` "Theo Pup" | `doAction` (new) | whole-body action (`ActionPerformed`, new) | 1–2 |

Per mode:

- **catchIt.** Three pictures fall in three lanes; the spoken word names one.
  The child leans left/right to stand under it. The picture in the child's lane
  when pictures reach the catch line is the answer. Fall time = the level's
  time limit. While the player is lost the clock stops (existing contract).
- **memoryFlip.** One "find my pair" question: a target card is face-up
  (picture), 3–5 candidate cards (words) are shown for 2 s ("peek") and turn
  face-down; the child holds a hand on a card for 1 s to flip it. Correct flip =
  correct; any other flip = wrong. Fits `ChoiceQuestion`, so the question count,
  stars and review logic stay as is.
- **balloonPop.** The prompt is a picture; balloons carry words that are
  spelled alike (edit distance ≤ 2 inside the same grade pool). The child holds
  a hand on a balloon for 0.6 s to pop it. Holding, not touching, so sweeping
  across a balloon never pops it.
- **yesNo.** A picture plus a spoken and written statement ("This is a dog.").
  Left hand up = Đúng, right hand up = Sai. Both hands up, or an unreliable
  frame, produces no event, so nothing is graded. False statements are built
  from the item's `distractorIds`. Guessing wins 50 %, so a level asks ≥ 10
  questions and the statement is true only 50 % of the time.
- **puppySays.** The spoken command ("Hands up!") names an action from a small
  set: jump, hands up, clap, squat. The round is correct when the detector
  reports that action. Other actions or silence never produce "Sai": the round
  ends with the neutral "Hết giờ" and a hint ("Pup chưa thấy rõ…"), the same
  philosophy as today's timeout. The skeleton overlay shows joints only; no
  camera image is shown or stored.

## 3. Architecture

```
HomeScreen ──► ModePickerScreen ──► GameController(grade, level, mode?)
                                       │  _modes: chosen mode, or all modes valid for the grade
                                       ▼
 QuestionGenerator (modes → forms) ─► PlannedQuestion(mode, question)
                                       ▼
 GameController._makeRound ─► Round  (CatchItRound | HoldPickRound | YesNoRound | ActionRound)
                                       ▲
 PoseSession ─ LaneTracker / CursorTracker+HoldTracker / HandSideDetector / ActionDetector
```

### 3.1 Enum, content and generator

- `ModeKind` gains `catchIt, memoryFlip, balloonPop, yesNo, puppySays`.
  `ContentItem.fromJson` already rejects unknown mode strings, so item files
  must be tagged by a one-shot tool (§3.5).
- `QuestionForm` gains `memoryMatch, popWord, trueFalse, doAction`.
  `_modeForms` in `question_generator.dart` maps each mode to its form(s).
- New question types reuse `ChoiceQuestion` (memoryMatch, popWord, trueFalse
  with 2 choices) so correctness, review ("Ôn lại") and the history store need
  no change. `doAction` adds `ActionQuestion(itemId, ttsText, action)`.
- Mode availability by grade is one constant table, shared by the picker and
  `GameController._modes` (today `_modes` is an inline grade check).

### 3.2 Rounds (one new class per input family)

All implement `Round` and its existing ordering contract (events before tick,
clock stops while the player is lost, result set once).

- `CatchItRound`: lane events; `result` is decided at the catch line.
- `HoldPickRound`: used by memoryFlip and balloonPop; consumes
  `HoldTracker` completion for `choice:<i>`; shares tap fallback with DragSpell
  (`GameController.holdTarget`).
- `YesNoRound`: `HandRaised(side)` → choice 0 (left) / 1 (right).
- `ActionRound`: `ActionPerformed(action)`; never returns `RoundResult.wrong`.

### 3.3 Input (`lib/input`)

- `HandSideDetector` (new): like `RaiseHandsDetector` but per hand; fires
  `HandRaised(left|right)` once after 500 ms above the nose, re-arms when the
  hand comes down; both raised ⇒ no event; same doubtful-frame grace.
  Selfie mirroring is decided once, in one place, and tested.
- `ActionDetector` (new): geometric rules on existing landmarks with a
  confidence gate. Jump reuses `JumpDetector`; hands up reuses
  `RaiseHandsDetector`; clap = wrists closer than a fraction of shoulder width
  after being apart; squat = hip height drops ≥ a fraction of torso length.
  Thresholds are calibrated per player by the existing `Calibrator`.
- New `GameInputEvent` subtypes: `HandRaised(side)`, `ActionPerformed(action)`.

### 3.4 UI

- `ModePickerScreen`: 3×3 grid + shuffle button, built from the same component
  kit as the redesigned screens. Tiles show name, grade range and input icon.
- One screen per new mode, built from shared parts (play header, sticker card,
  hold-ring cursor). The header, prompt pill and caption rules from the existing
  play screens apply: a single caption line, no answer text before the answer.
- Mode choice is session state only; progress (stars, unlocks, history) stays
  keyed by (grade, level), so any mode counts towards the same level.

### 3.5 Content tooling

`tools/tag_modes.py` (idempotent, run in CI as a check) adds mode tags:

- `memoryFlip`, `yesNo`, `catchIt`: items with an image (and distractors for
  yesNo).
- `balloonPop`: items with ≥ 2 spelling-similar words in the same grade pool.
- `puppySays`: not item-based; reads new `assets/content/actions.json`
  (command text, TTS text, action id, grades), authored by us.

`content_validity_test.dart` gains the matching rules (e.g. every `balloonPop`
item has ≥ 2 usable distractors; every unit-level fill still succeeds).

## 4. Rules carried over (acceptance checks per mode)

- Uncertain input: no event ⇒ no grade. Timeout is neutral ("Hết giờ").
- Answer never leaks: caption, `Semantics` labels and TTS are reviewed per form
  (tests assert the correct answer text is absent before the answer).
- Layout: widget tests at 800×360 and 1280×720 (no overflow), text ≥ 28 sp
  during play, targets ≥ 56 dp.
- Privacy: no new packages; the architecture test still passes.
- Touch fallback: hold modes keep tap; lane/hand/action modes have none (same
  as LaneJump today); recorded in `docs/known-limitations.md`.

## 5. Testing

- Unit: each Round (ordering contract, lost/found, timeout), both detectors
  (left only, right only, both ⇒ none, dropout, re-arm), generator forms,
  tagging tool, mode-availability table.
- Widget: picker (grade filtering, shuffle), each screen at both sizes,
  semantics without answer leaks.
- Device spikes (cannot run here): `ActionDetector` false/miss rates, hand-side
  mirroring, balloon hold time for 6–8 year-olds. Results gate `puppySays`.

## 6. Risks

- `puppySays` accuracy is unknown until a device spike; it ships last and
  behind its own enable flag.
- `yesNo` and `catchIt` are 1-in-2/3 guessable; mitigated by question count
  and the neutral-timeout rule, but stars are less meaningful than in
  LaneJump. Accept and measure in child playtests.
- Vocabulary images are still placeholders: picture-based modes look weak until
  real art exists.

## 7. Decisions made here (flag if wrong)

1. Any mode counts towards the same (grade, level) progress and unlocks.
2. memoryFlip is "find the pair of one target" (fits the question model), not a
   multi-pair board.
3. "Chơi" on Home keeps today's per-grade mix; the picker is an extra entry.
4. `puppySays` has no "wrong" outcome.

## 8. Sequencing (each wave: own plan, review, merge)

- **Wave 0, UI kit.** Space Puppy mascot, design tokens, HUD, sticker cards,
  buttons, font bundling, relaunch of the existing screens. Separate spec.
- **Wave 1.** Mode framework + picker + `memoryFlip`, `balloonPop`, `catchIt`.
- **Wave 2.** `HandSideDetector` + `yesNo`.
- **Wave 3.** `ActionDetector` + `puppySays`, after the device spike.
