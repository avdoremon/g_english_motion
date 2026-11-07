# UI Kit + Space Puppy (Wave 0) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Re-skin the existing game with the approved redesign (palette, Fredoka 5-size type scale, sticker cards, HUD, buttons) and replace the mascot with Space Puppy, without changing any game logic.

**Architecture:** Keep the public API of `TinTin` (`state`, `size`, `pulse`, `TinTinState`) and swap its painter for the Space Puppy drawing, so the 9 call sites do not change. Add a small `lib/ui/kit/` layer (tokens already live in `AppTheme`; widgets: `StickerCard`, `BigButton`, `RoundIconButton`, `StarRow`, `HudBar`) and re-skin Home, PlayHeader and Result on it. Other screens pick up the theme automatically.

**Tech Stack:** Flutter 3.47.9, Dart, `CustomPaint`, bundled Fredoka font.

**Spec:** Design canvas "Tin Tin English — thiết kế lại giao diện game" (boards Main, LaneJump, DragSpell, SkyShoot, SayIt, Result, System, CharPuppy; generator `ui-canvas/gen.py`, `chars.py`); `docs/superpowers/specs/2026-11-07-new-game-modes-design.md` §8 (sequencing). Palette and type scale below are copied from the canvas "System" board.

## Global Constraints

- Palette (replaces current): night `#1B1F4B`, ink `#0E1033`, panel `#262B6B`, panel-light `#323896`, purple `#6C4DFF`, sky `#35D0FF`, star-yellow `#FFD23F`, coral `#FF6B6B`, correct-green `#3DDC97`, orange `#FFB84D`, muted `#C9CCF5`, text `#FFFFFF`.
- Type: Fredoka, exactly 5 sizes: Display 56/700, Title 48/700, Heading 36/700, Play text 28/600, Label 24/500. Play text never below 28 sp.
- Touch targets ≥ 56 dp, ≥ 12 dp apart. Buttons and cards never wrap text to a 2nd line (single line, `maxLines: 1`, shrink via `FittedBox` before overflowing); only paragraphs wrap.
- No overflow at 800×360 and 1280×720 on every re-skinned screen.
- Game logic, star thresholds, level table, content, ProgressStore untouched. No network libraries; fonts are bundled assets.
- Mascot semantics labels, reduce-motion behaviour and cheer/dance timing (3 cycles × 1.2 s) keep working as today.

## Review Focus

- Large system font scale (textScaler 1.3): Home buttons and cards still single-line, no overflow.
- `TinTinState.sad` must stay friendly (no "wrong answer" face that shames a child) and keep its existing semantics label.
- Reduce-motion on: Puppy does not animate; still conveys state.
- Font asset missing/fails to load: app still renders with the fallback family, no crash.
- Existing tests that pin old palette/font (`test/ui/theme_mascot_test.dart`) are updated deliberately, not deleted.

---

### Task 1: Tokens and Fredoka font

**Files:**
- Modify: `lib/ui/theme/app_theme.dart`, `pubspec.yaml`, `test/ui/theme_mascot_test.dart`
- Create: `assets/fonts/Fredoka-*.ttf` (from google/fonts `ofl/fredoka`, SIL OFL; add `OFL.txt` beside it)
- Test: `test/ui/theme_mascot_test.dart`

**Interfaces:**
- Produces: `AppTheme` constants `background` (night), `ink`, `surface` (panel), `surfaceLight`, `purple`, `accent` (sky), `yellow`, `pink`→renamed `coral`, `green`, `orange`, `muted`, `text`; `AppTheme.fontFamily = 'Fredoka'`; `AppTheme.textStyles` getters `display`, `title`, `heading`, `play`, `label` (sizes above).
- Keep existing names where tests/screens use them (`background`, `surface`, `accent`, `yellow`, `green`, `orange`, `purple`, `text`, `muted`); add `coral`, keep `pink` as a deprecated alias of `coral` so screens compile.

- [ ] **Step 1: Update the failing test** — in `theme_mascot_test.dart` change the palette expectations to the new hex values above, `expect(t.textTheme.bodyLarge!.fontFamily, 'Fredoka')`, `bodyLarge.fontSize >= 28`, and add `test('type scale has exactly five sizes')` asserting `{display,title,heading,play,label}.map((s)=>s.fontSize)` equals `{56,48,36,28,24}`.
- [ ] **Step 2: Run** `flutter test test/ui/theme_mascot_test.dart` — expect FAIL on colours/font.
- [ ] **Step 3: Download** Regular/Medium/SemiBold/Bold Fredoka TTFs from `https://github.com/google/fonts/tree/main/ofl/fredoka` into `assets/fonts/`; declare family `Fredoka` with weights 500/600/700 in `pubspec.yaml`. If the download is refused by the network allowlist, stop and report; do not substitute another font silently.
- [ ] **Step 4: Implement** the constants and `textStyles` in `app_theme.dart`; map `textTheme.bodyLarge` to Play text, `headlineLarge` Heading, `displayLarge` Display, `labelLarge` Label; `AppTheme.dark()` uses `fontFamily: 'Fredoka'`.
- [ ] **Step 5: Run** `flutter analyze && flutter test` — expect all green (fix any test that pinned `pink`/old hex by updating to the new value).
- [ ] **Step 6: Commit** `feat(ui): new palette, Fredoka type scale`.

### Task 2: Space Puppy painter inside TinTin

**Files:**
- Modify: `lib/ui/mascot/tin_tin.dart`
- Create: `lib/ui/mascot/space_pup_painter.dart`
- Test: `test/ui/space_pup_test.dart`

**Interfaces:**
- Consumes: `TinTinState {idle, happy, sad, cheer, dance}`, existing `TinTin({state, size, pulse})` constructor and semantics label strings (unchanged).
- Produces: `class SpacePupPainter extends CustomPainter { SpacePupPainter({required TinTinState state, required double t}); }` — `t` is 0..1 animation phase; draws helmet, ears, face per state from canvas board "CharPuppy" (`chars.py: puppy(e)` is the reference for shapes and colours).

- [ ] **Step 1: Write failing tests** in `space_pup_test.dart`: (a) `TinTin` renders for every `TinTinState` at size 96 with no exception; (b) semantics label for each state equals the pre-change string (read them from the current file and copy verbatim); (c) with `MediaQueryData(disableAnimations: true)` no `AnimationController` ticker is active after `pump(Duration(seconds: 5))` (`tester.hasRunningAnimations == false`); (d) golden-free pixel check: painting `sad` and `happy` to a 96×96 image yields different bytes.
- [ ] **Step 2: Run** `flutter test test/ui/space_pup_test.dart` — expect FAIL (painter missing / bytes equal).
- [ ] **Step 3: Implement** `SpacePupPainter` translating the SVG shapes in `chars.py:puppy` into `Canvas` calls (viewBox scale to `size`); `sad` = soft worried brows, no tears; `cheer`/`dance` use `t` for arm/ear offset. Replace the old painter in `tin_tin.dart`; keep controller timing and reduce-motion handling untouched.
- [ ] **Step 4: Run** `flutter test test/ui` — expect green.
- [ ] **Step 5: Commit** `feat(ui): Space Puppy mascot`.

### Task 3: Kit widgets

**Files:**
- Create: `lib/ui/kit/sticker_card.dart`, `big_button.dart`, `round_icon_button.dart`, `star_row.dart`, `hud_bar.dart`, `kit.dart` (barrel)
- Test: `test/ui/kit_test.dart`

**Interfaces:**
- Produces:
  - `StickerCard({required Widget child, double tilt = 0, Color? fill})` — white fill, 5 px ink border, rounded 24, optional tilt.
  - `BigButton({required String label, required VoidCallback? onPressed, IconData? icon, Color color = AppTheme.yellow, Color onColor = AppTheme.ink})` — min height 64, single-line label (`FittedBox(scaleDown)`), semantics label = `label`.
  - `RoundIconButton({required IconData icon, required String semanticLabel, required VoidCallback onPressed, double size = 56})`.
  - `StarRow({required int earned, int total = 3, double size = 40})`.
  - `HudBar({required int stars, required double timeFraction, required Widget? trailing})` — compact top bar.

- [ ] **Step 1: Failing tests** `kit_test.dart`: `BigButton` with a 24-char Vietnamese label in a 200 dp wide box does not overflow and its rendered size ≥ 56 high; `RoundIconButton` hit size ≥ 56×56 for `size: 48` input (padding grows it); `StarRow(earned:2)` shows 2 filled + 1 empty (find by `Key('star-on-i')`/`Key('star-off-i')`); everything survives `textScaler: TextScaler.linear(1.3)` without overflow exception.
- [ ] **Step 2: Run** — FAIL (files missing).
- [ ] **Step 3: Implement** the widgets to the interfaces; colours/sizes from `AppTheme`; borders/shadows per canvas "System" board.
- [ ] **Step 4: Run** `flutter test test/ui/kit_test.dart` — PASS.
- [ ] **Step 5: Commit** `feat(ui): kit widgets`.

### Task 4: Re-skin Home, PlayHeader, Result

**Files:**
- Modify: `lib/ui/screens/home_screen.dart`, `play_header.dart`, `result_screen.dart`
- Test: existing `test/ui/home_screen_test.dart`, `result_screen_test.dart`, `play_screen_test.dart` (update finders only where widgets changed); add size tests.

**Interfaces:**
- Consumes: Task 3 kit widgets, Task 2 `TinTin`, `PlayHeader`'s current constructor (keep unchanged), `HomeScreen`/`ResultScreen` current constructors (keep unchanged).

- [ ] **Step 1: Failing tests:** in `home_screen_test.dart` the size loop `[Size(1280,720), Size(800,360)]` additionally asserts `tester.takeException() == null`, every `BigButton`/`RoundIconButton` ≥ 56×56, and no `Text` in a button has `maxLines > 1` or wraps (assert `tester.getSize(find.text('Luyện nói')).height` < 2× font size). Same size loop for `ResultScreen` with 0, 1, 3 stars. Add `textScaler 1.3` case for Home.
- [ ] **Step 2: Run** — FAIL where layouts are old.
- [ ] **Step 3: Re-skin** per canvas boards "Main (Home)" and "Result": Home = Puppy + title left, mode/level controls in sticker cards right, "Luyện nói" as a normal-width `BigButton` (the earlier overflow bug); Result = `StarRow` + Puppy cheer/happy/sad-by-stars + two buttons; `PlayHeader` = `HudBar` (stars, timer bar, close/settings `RoundIconButton`s). No behaviour or callback changes.
- [ ] **Step 4: Run** `flutter analyze && flutter test` — all green.
- [ ] **Step 5: Commit** `feat(ui): re-skin home, header, result`.

### Task 5: Play screens, remaining screens and docs

**Files:**
- Modify: `lib/ui/screens/{lane_jump,drag_spell,sky_shoot,say_it}_screen.dart`, calibration/permission/safety/break/camera-problem screens (only where hard-coded colours/sizes/fonts exist), `docs/known-limitations.md`
- Test: existing screen tests

**Interfaces:** Consumes kit + tokens; no signature changes.

- [ ] **Step 1: Failing test:** add `test/ui/no_hardcoded_style_test.dart` that greps `lib/ui` for `fontSize:` literals outside `app_theme.dart` that are not in `{56,48,36,28,24}` and for `Color(0x` literals outside `app_theme.dart`/painters, allow-list in the test; expect FAIL listing offenders.
- [ ] **Step 2: Replace** offenders with `AppTheme.textStyles.*`/tokens; play text ≥ 28.
- [ ] **Step 3: Run** `flutter analyze && flutter test` — green; run the 800×360 and 1280×720 size tests for every screen test file.
- [ ] **Step 4: Update** `docs/known-limitations.md` (Fredoka bundled, Puppy replaces old mascot, logo still Jump Star robot — redraw pending).
- [ ] **Step 5: Commit** `feat(ui): apply tokens to all screens`.
