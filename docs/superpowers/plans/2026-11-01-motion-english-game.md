# Tin Tin English (Motion English Game) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Game Flutter/Flame học tiếng Anh tiểu học (lớp 1–5, Global Success) điều khiển bằng chuyển động qua camera điện thoại, chiếu lên TV.

**Architecture:** Logic game viết bằng Dart thuần (input events, content, level, từng mode) để kiểm thử không cần camera; lớp Flame chỉ vẽ và nối các luồng sự kiện. Camera và MediaPipe Pose nằm sau giao diện `PoseEventSource`, thay được bằng nguồn giả.

**Tech Stack:** Flutter (>= 3.13), Dart, Flame, MediaPipe Pose Landmarker (Android, CameraX), `flutter_tts`, `shared_preferences`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-01-motion-english-game-design.md`

## Global Constraints

- Android trước (minSdk 24, máy kiểm thử Galaxy S24 Ultra, Android 17); iOS để sau.
- Hướng điều khiển A: chỉ MediaPipe Pose, không dùng Hand Landmarker.
- Phát hiện nhảy: hông và vai dịch lên >= 12% chiều cao thân so với chuẩn hiệu chỉnh; debounce 600 ms.
- Hold: 1 giây để nhặt/thả chữ và bấm "Kiểm tra". Kéo dây: 4 lần kéo, hai tay luân phiên.
- SkyShoot: tối đa 3 lượt bắn mỗi câu; hết lượt coi như sai.
- 5 level mỗi lớp, bảng level đúng như spec mục 5 (số câu 8/10/10/12/12; thời gian 20/18/15/12/10 giây; đáp án 3/3/4/4/4). Câu nhiều bước cộng 50% thời gian.
- 100 điểm mỗi câu đúng. Sao: 1 sao từ 50%, 2 sao từ 75%, 3 sao từ 90%. Mở khóa level N+1 khi level N có >= 1 sao.
- Random: pool mỗi level >= 2 lần số câu; đáp án đúng không cùng vị trí quá 2 câu liên tiếp; ưu tiên mục chưa hỏi gần đây; câu sai xếp lại một lần cuối lượt.
- SayIt (đọc to): 3 từ mỗi ván; mỗi từ rơi từ trên xuống hoặc đi từ phải qua trái; có kết quả thì hiện đúng/sai rồi nổ và biến mất; từ chạm đáy/mép trái chưa có kết quả tính là sai. Nhận dạng bằng Android `SpeechRecognizer` `en-US`; đúng khi một kết quả thay thế chuẩn hóa trùng từ đích hoặc `spokenVariants`, và điểm tin cậy >= 0,3 nếu có; không chấm gần đúng theo khoảng cách chữ cái. Tắt nhạc/hiệu ứng khi đang nghe. Cần quyền `RECORD_AUDIO`. Không nhận dạng được thì ẩn mini-game, các chế độ khác vẫn chơi.
- Không đăng nhập; tiến độ lưu cục bộ; quảng cáo chỉ banner nhỏ ở góc.
- Repo: `avdoremon/g_english_motion`. Tên package Dart: `g_english_motion`. Nội dung từ vựng tự soạn theo chủ đề unit, không sao chép văn bản sách.

## Review Focus

- Mất dấu người chơi giữa chừng (ra khỏi khung hình): đồng hồ phải tạm dừng và game hiện hướng dẫn, không tính sai.
- Hai người cùng trong khung hình: chỉ theo dõi người đã hiệu chỉnh ban đầu, không nhảy sang người khác.
- Từ có chữ cái lặp (ví dụ "apple" có hai chữ p): ghép bằng bất kỳ chữ p nào đều đúng.
- Pool nhỏ hơn số câu cần (unit mới ít mục): vẫn đủ số câu, cho lặp lại thay vì thiếu câu.
- TTS hoặc nhận dạng giọng nói không khả dụng (không có dịch vụ, mất mạng, từ chối quyền micro) hay ứng dụng bị đưa xuống nền giữa level: không crash, hiển thị chữ thay cho giọng đọc, ẩn SayIt, đồng hồ tạm dừng.

---

## File Structure

```
lib/
  input/       pose_types.dart, pose_events.dart, calibration.dart, jump_detector.dart,
               lane_mapper.dart, hold_tracker.dart, pull_detector.dart,
               mock_pose_source.dart, mediapipe_pose_source.dart
  content/     models.dart, content_repository.dart, history_store.dart, question_generator.dart
  levels/      level_config.dart, scoring.dart
  modes/       lane_jump.dart, drag_spell.dart, sky_shoot.dart, say_it.dart
  speech/      word_judge.dart, speech_source.dart, android_speech_source.dart
  audio/       tts_service.dart
  progress/    progress_store.dart
  ui/          theme/ (token theo phương án đồ họa được chọn), screens/, mascot/
assets/content/grade1 ... grade5/  (JSON theo unit)
test/          phản chiếu cấu trúc lib/
```

## Task 0: Spike đo đạc phát hiện nhảy (vứt đi)

**Files:** `spike/` (không merge vào `main`, ghi kết quả vào `docs/superpowers/notes/jump-spike.md`)

**Interfaces:** Produces: số liệu độ trễ (ms) và tỉ lệ phát hiện đúng trên S24 Ultra; ngưỡng đề xuất thay cho 12% nếu cần.

- [ ] **Step 1:** Dựng app Flutter tối thiểu hiện camera + landmark hông/vai (dùng plugin `flutter_mp_pose_landmarker`), log độ cao hông chuẩn hóa mỗi khung hình.
- [ ] **Step 2:** Một người lớn và một bé (nếu có) nhảy 20 lần mỗi người ở 2,5 m, phòng sáng và phòng tối; ghi số lần nhảy bị bỏ sót, số lần báo nhầm, và độ trễ từ lúc chân rời đất (quay video 60 fps) tới lúc log báo.
- [ ] **Step 3:** Ghi kết quả vào notes. Tiêu chí qua: bỏ sót <= 10%, báo nhầm <= 5%, độ trễ <= 250 ms. Nếu không qua, chỉnh ngưỡng và ghi lại; cập nhật Global Constraints cho khớp trước khi làm Task 3.
- [ ] **Step 4:** Spike nhận dạng giọng nói trên cùng app: gọi `SpeechRecognizer` `en-US` (thử cả bản trên máy nếu `isOnDeviceRecognitionAvailable`) cho 10 từ lớp 3 (ví dụ hand, head, red, blue, mother, school, rabbit, window, kitchen, teacher); mỗi từ đọc 5 lần bởi người lớn và (nếu có) một bé, ở 1 m và 2,5 m, TV tắt và TV bật tiếng. Ghi tỉ lệ nhận đúng ở kết quả đầu, ở top-N kết quả thay thế, có/không có mạng, và các biến thể nhận sai lặp lại (đưa vào `spokenVariants`). Tiêu chí qua cho người lớn: >= 80% đúng trong top-N ở 2,5 m với TV tắt tiếng; nếu bé dưới 60% hoặc cần mạng bắt buộc, ghi rõ để người dùng quyết định phạm vi SayIt (chỉ lớp 3–5, hoặc bật tùy chọn).
- [ ] **Step 5:** Commit notes. Không merge mã spike.

## Task 1: Khởi tạo dự án Flutter

**Files:** Create `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`, `test/smoke_test.dart`, `.gitignore`; Modify `README.md`.

**Interfaces:** Produces: dự án chạy được `flutter test` và `flutter analyze` sạch.

- [ ] **Step 1:** Test `smoke_test.dart`: `testWidgets('app builds', ...)` pump `GEnglishMotionApp` và `expect(find.text('Tin Tin English'), findsOneWidget)`.
- [ ] **Step 2:** `flutter test` — kỳ vọng FAIL (chưa có widget).
- [ ] **Step 3:** `flutter create --org vn.avdoremon --platforms android .`, thêm phụ thuộc `flame`, `flutter_tts`, `shared_preferences`; tạo `GEnglishMotionApp` hiển thị chữ "Tin Tin English".
- [ ] **Step 4:** `flutter test && flutter analyze` — kỳ vọng PASS.
- [ ] **Step 5:** Commit `feat: scaffold flutter app`.

## Task 2: Kiểu dữ liệu pose, sự kiện và hiệu chỉnh

**Files:** Create `lib/input/pose_types.dart`, `pose_events.dart`, `calibration.dart`, `mock_pose_source.dart`; Test `test/input/calibration_test.dart`.

**Interfaces:**
- Produces:
  - `enum PoseJoint { leftShoulder, rightShoulder, leftHip, rightHip, leftWrist, rightWrist }`
  - `class Landmark { final double x, y, confidence; }` (x, y chuẩn hóa 0..1, y hướng xuống)
  - `class Pose { final Map<PoseJoint, Landmark> joints; final Duration timestamp; }`
  - `sealed class GameInputEvent`: `LaneChanged(int lane)`, `Jumped()`, `CursorMoved(double x, double y)`, `Pulled(Hand hand)`, `PlayerLost()`, `PlayerFound()`; `enum Hand { left, right }`
  - `class Calibration { final double torsoHeight, centerX, baselineHipY, baselineShoulderY; static Calibration? fromPose(Pose p); }` — trả `null` nếu thiếu khớp hoặc confidence < 0.5
  - `abstract class PoseEventSource { Stream<GameInputEvent> get events; Future<Calibration?> calibrate(); }`; `MockPoseSource` phát chuỗi `Pose` ghi sẵn.

- [ ] **Step 1:** Test `calibration_test.dart`: pose hông y=0.6, vai y=0.3 → `torsoHeight == 0.3`, `baselineHipY == 0.6`; pose thiếu `leftHip` → `Calibration.fromPose` trả `null`; confidence 0.3 → `null`.
- [ ] **Step 2:** Chạy test, kỳ vọng FAIL.
- [ ] **Step 3:** Cài các kiểu trên. `fromPose` lấy trung điểm hai hông và hai vai.
- [ ] **Step 4:** Chạy test, kỳ vọng PASS.
- [ ] **Step 5:** Commit `feat(input): pose types and calibration`.

## Task 3: JumpDetector và LaneMapper

**Files:** Create `lib/input/jump_detector.dart`, `lane_mapper.dart`; Test `test/input/jump_detector_test.dart`, `lane_mapper_test.dart`.

**Interfaces:**
- Consumes: `Pose`, `Calibration` (Task 2).
- Produces:
  - `class JumpDetector { JumpDetector(Calibration c, {double threshold = 0.12, Duration debounce = const Duration(milliseconds: 600)}); bool update(Pose p); }` — trả `true` đúng một lần khi cả hông lẫn vai (trung bình) cao hơn chuẩn >= `threshold * torsoHeight`; chỉ nạp lại khi người chơi hạ xuống dưới nửa ngưỡng và hết debounce.
  - `int laneFor(double hipX, double centerX, int laneCount, {double laneWidth = 0.18});`

- [ ] **Step 1:** Test JumpDetector với torsoHeight 0.3 (ngưỡng nâng = 0.036): chuỗi hông y 0.60 → 0.55 trả `true` đúng một lần; chuỗi tiếp theo vẫn trên cao trả `false`; nhảy lại sau 300 ms (trong debounce) trả `false`; nhảy lại sau khi hạ xuống và 700 ms trả `true`; dịch hông 0.02 (dưới ngưỡng) trả `false`.
- [ ] **Step 2:** Test `laneFor` (center 0.5, 4 làn, width 0.18): hipX 0.5 → 2; 0.31 → 0; 0.4 → 1; 0.69 → 3; 0.0 → 0 (kẹp biên); 1.0 → 3.
- [ ] **Step 3:** Chạy test, kỳ vọng FAIL.
- [ ] **Step 4:** Cài hai hàm/lớp với chữ ký trên.
- [ ] **Step 5:** Chạy test, kỳ vọng PASS.
- [ ] **Step 6:** Commit `feat(input): jump detector and lane mapper`.

## Task 4: HoldTracker và PullDetector

**Files:** Create `lib/input/hold_tracker.dart`, `pull_detector.dart`; Test `test/input/hold_tracker_test.dart`, `pull_detector_test.dart`.

**Interfaces:**
- Produces:
  - `class HoldProgress { final String? targetId; final double progress; final bool completed; }`
  - `class HoldTracker { HoldTracker({Duration holdTime = const Duration(seconds: 1)}); HoldProgress update(String? targetId, Duration now); }` — đổi mục tiêu hoặc `null` thì đặt lại; `completed` chỉ `true` một lần cho mỗi lần giữ.
  - `class PullDetector { PullDetector(Calibration c, {int requiredPulls = 4, double minTravel = 0.4}); int update(Pose p); bool get done; }` — một lần kéo là cổ tay đi xuống >= `minTravel * torsoHeight` rồi đi lên >= nửa quãng đó; chỉ tính khi tay khác tay của lần kéo trước (lần đầu tính tay nào cũng được); `update` trả số lần kéo hợp lệ hiện có.

- [ ] **Step 1:** Test HoldTracker: giữ `'a'` từ 0 đến 1000 ms → `completed == true` tại 1000 ms, `progress == 0.5` tại 500 ms; chuyển sang `'b'` ở 600 ms rồi quay lại `'a'` → tiến độ đặt lại; `null` → `progress == 0`.
- [ ] **Step 2:** Test PullDetector: torsoHeight 0.3, tay trái xuống 0.15 rồi lên → 1 lần; tay trái kéo tiếp ngay → vẫn 1; tay phải kéo → 2; sau 4 lần xen kẽ `done == true`; chuyển động 0.05 (dưới ngưỡng) → không tính.
- [ ] **Step 3:** Chạy test, kỳ vọng FAIL.
- [ ] **Step 4:** Cài theo chữ ký.
- [ ] **Step 5:** Chạy test, kỳ vọng PASS.
- [ ] **Step 6:** Commit `feat(input): hold tracker and pull detector`.

## Task 5: Mô hình nội dung và nạp JSON

**Files:** Create `lib/content/models.dart`, `content_repository.dart`, `assets/content/grade3/sample.json` (mẫu), `docs/content/unit-map.md`; Test `test/content/content_repository_test.dart`.

**Interfaces:**
- Produces:
  - `class ContentItem { final String id, word, ttsText; final String? image; final List<String> sentencePatterns, distractors, spokenVariants; final List<ModeKind> modes; }` (`spokenVariants` mặc định rỗng)
  - `enum ModeKind { laneJump, dragSpell, skyShoot, sayIt }`
  - `class Unit { final int grade; final String id, title; final List<ContentItem> items; }`
  - `class ContentRepository { ContentRepository(this.units); static Future<ContentRepository> loadFromAssets(AssetBundle b); List<Unit> unitsFor(int grade); List<ContentItem> itemsFor(int grade, {required List<String> unitIds}); }`
  - JSON schema: `{"grade":3,"unit":"u04","title":"Our bodies","items":[{"id":"u04-hand","word":"hand","ttsText":"hand","image":"hand.png","sentencePatterns":["This is my hand."],"distractors":["head","arm"],"modes":["dragSpell","skyShoot"]}]}`

- [ ] **Step 1:** Test: nạp chuỗi JSON mẫu trên → `unitsFor(3).single.title == 'Our bodies'` và `itemsFor(3, unitIds: ['u04']).single.word == 'hand'`; JSON thiếu `id` → ném `FormatException` có tên file.
- [ ] **Step 2:** Chạy test, kỳ vọng FAIL.
- [ ] **Step 3:** Cài mô hình và bộ nạp; `loadFromAssets` đọc mọi `assets/content/grade*/*.json` qua `AssetManifest`.
- [ ] **Step 4:** Đối chiếu mục lục chính thức Global Success lớp 1–5 (SGK hoặc trang NXB Giáo dục VN) và ghi tên unit đúng vào `docs/content/unit-map.md` (bảng grade/unit/title/chủ đề). Đây là nguồn duy nhất cho Task 14.
- [ ] **Step 5:** Chạy test, kỳ vọng PASS. Commit `feat(content): models, loader, unit map`.

## Task 6: LevelConfig và chấm điểm

**Files:** Create `lib/levels/level_config.dart`, `scoring.dart`; Test `test/levels/level_config_test.dart`, `scoring_test.dart`.

**Interfaces:**
- Produces:
  - `enum HintMode { full, partial, none }`
  - `class LevelConfig { final int level, questionCount, choiceCount, unitSpan; final Duration perQuestion; final HintMode hints; Duration timeFor({required bool multiStep}); static LevelConfig forLevel(int level); }`
  - `class Scoring { static int points(int correct) => correct * 100; static int stars(int correct, int total); static bool unlocksNext(int stars) => stars >= 1; }`

- [ ] **Step 1:** Test: `forLevel(1)` có `questionCount 8`, `perQuestion 20s`, `choiceCount 3`, `hints full`; `forLevel(5)` có `12`, `10s`, `4`, `none`; `timeFor(multiStep: true)` của level 3 = 22,5 giây (15 × 1,5); `forLevel(6)` ném `RangeError`.
- [ ] **Step 2:** Test `stars`: 4/8 → 1; 3/8 → 0; 6/8 → 2; 9/10 → 3; 7/10 → 1; `points(7) == 700`.
- [ ] **Step 3:** Chạy test, kỳ vọng FAIL. Cài theo bảng spec.
- [ ] **Step 4:** Chạy test, kỳ vọng PASS. Commit `feat(levels): config and scoring`.

## Task 7: QuestionGenerator với random hóa

**Files:** Create `lib/content/history_store.dart`, `question_generator.dart`; Test `test/content/question_generator_test.dart`.

**Interfaces:**
- Consumes: `ContentRepository`, `LevelConfig`, `ModeKind`.
- Produces:
  - `abstract class HistoryStore { List<String> recentIds(); Future<void> record(List<String> askedIds); Future<void> recordWrong(String id); Set<String> wrongIds(); }`; `InMemoryHistoryStore` để kiểm thử (bản lưu thật ở Task 12).
  - `sealed class Question { String itemId; String ttsText; }` với `ChoiceQuestion(prompt, choices, correctIndex)`, `SpellQuestion(word, tiles, image)`, `OrderQuestion(words, correctOrder)`.
  - `class QuestionGenerator { QuestionGenerator(ContentRepository repo, HistoryStore history, Random rng); Future<List<Question>> generate({required int grade, required LevelConfig level, required ModeKind mode, required List<String> unitIds}); }`

- [ ] **Step 1:** Các test (dùng `Random(42)`): (a) không câu nào lặp `itemId` trong một lượt khi pool đủ; (b) với 200 lượt sinh, `correctIndex` không bao giờ giống nhau quá 2 câu liên tiếp; (c) lượt 2 liền sau lượt 1 (cùng history) có ít nhất 70% mục khác lượt 1 khi pool = 2 × số câu; (d) pool nhỏ hơn số câu → vẫn trả đúng `questionCount` câu, chỉ lặp sau khi dùng hết pool (Review Focus); (e) mọi `ChoiceQuestion` có đúng `choiceCount` đáp án và đáp án nhiễu không trùng đáp án đúng, thiếu nhiễu trong unit thì lấy từ unit khác cùng lớp; (f) `SpellQuestion.tiles` là hoán vị của `word` và không bằng `word` (từ >= 2 chữ cái khác nhau); (g) `wrongIds` của lượt trước được ưu tiên ở lượt sau nhưng không nằm ở câu đầu tiên.
- [ ] **Step 2:** Chạy test, kỳ vọng FAIL.
- [ ] **Step 3:** Cài bộ sinh: chọn ứng viên theo trọng số (chưa hỏi gần đây > sai gần đây > còn lại), xáo vị trí đáp án rồi sửa chuỗi đáp án trùng vị trí quá 2 liên tiếp bằng hoán vị cục bộ.
- [ ] **Step 4:** Chạy test, kỳ vọng PASS. Commit `feat(content): randomized question generator`.

## Task 8: Logic LaneJump (lớp 1–2)

**Files:** Create `lib/modes/lane_jump.dart`; Test `test/modes/lane_jump_test.dart`.

**Interfaces:**
- Consumes: `ChoiceQuestion`, `GameInputEvent`.
- Produces: `class LaneJumpRound { LaneJumpRound(ChoiceQuestion q, {required Duration timeLimit}); void onEvent(GameInputEvent e); void tick(Duration dt); int get selectedLane; RoundResult? get result; }`; `enum RoundResult { correct, wrong, timeout }`. `LaneChanged` đổi `selectedLane`, `Jumped` chốt đáp án ở làn hiện tại.

- [ ] **Step 1:** Test: `LaneChanged(2)` rồi `Jumped()` với `correctIndex 2` → `correct`; chọn làn sai → `wrong`; `tick` đủ `timeLimit` mà chưa nhảy → `timeout`; `Jumped` trước khi có `LaneChanged` chốt làn mặc định (giữa); sau khi có `result`, sự kiện sau không đổi kết quả; `PlayerLost` làm `tick` không trừ giờ cho tới `PlayerFound`.
- [ ] **Step 2:** Chạy test, kỳ vọng FAIL. Cài. Chạy test, kỳ vọng PASS.
- [ ] **Step 3:** Commit `feat(modes): lane jump round logic`.

## Task 9: Logic DragSpell (lớp 3–5)

**Files:** Create `lib/modes/drag_spell.dart`; Test `test/modes/drag_spell_test.dart`.

**Interfaces:**
- Consumes: `SpellQuestion`, `OrderQuestion`, `HoldTracker` (Task 4).
- Produces: `class DragSpellRound { DragSpellRound.spell(SpellQuestion q, {required Duration timeLimit}); DragSpellRound.order(OrderQuestion q, {required Duration timeLimit}); void onHold(String targetId); void tick(Duration dt); RoundResult? get result; List<String?> get slots; }`. `targetId` có dạng `tile:<index>`, `slot:<index>`, `check`.

- [ ] **Step 1:** Test: giữ `tile:0` rồi `slot:1` đặt chữ vào ô 1; giữ `tile` của chữ đã đặt trả chữ về khay; `check` khi ô chưa đầy → không có `result`; đầy và đúng → `correct`; đầy và sai → `wrong`; "apple" ghép bằng chữ p thứ hai ở vị trí p đầu vẫn `correct` (Review Focus); hết giờ → `timeout`.
- [ ] **Step 2:** Chạy test, kỳ vọng FAIL. Cài (so sánh chuỗi chữ, không so danh tính ô chữ). Chạy test, kỳ vọng PASS.
- [ ] **Step 3:** Commit `feat(modes): drag spell round logic`.

## Task 10: Logic SkyShoot (lớp 3–5)

**Files:** Create `lib/modes/sky_shoot.dart`; Test `test/modes/sky_shoot_test.dart`.

**Interfaces:**
- Consumes: `ChoiceQuestion`, `PullDetector` (Task 4), `Jumped`, `Pulled`.
- Produces: `class SkyShootRound { SkyShootRound(ChoiceQuestion q, {required Duration timeLimit, required double Function() aimAt, required List<double> answerCenters, double hitRadius = 0.12}); void onEvent(GameInputEvent e); void tick(Duration dt); SkyPhase get phase; int get shotsLeft; RoundResult? get result; }`; `enum SkyPhase { aiming, reeling, resolved }`. `Jumped` trong `aiming` bắn tại `aimAt()`; trúng đáp án trong `hitRadius` → `reeling`; trượt → `shotsLeft--`; `shotsLeft == 0` → `wrong`. Đủ 4 `Pulled` xen kẽ trong `reeling` → chấm đáp án.

- [ ] **Step 1:** Test: `shotsLeft` ban đầu 3; bắn trượt hai lần → 1, vẫn `aiming`; trượt lần ba → `wrong`; bắn trúng đáp án đúng, 4 lần `Pulled` xen kẽ → `correct`; trúng đáp án sai và kéo đủ → `wrong`; `Jumped` khi đang `reeling` bị bỏ qua; hết giờ trong `reeling` → `timeout`.
- [ ] **Step 2:** Chạy test, kỳ vọng FAIL. Cài. Chạy test, kỳ vọng PASS.
- [ ] **Step 3:** Commit `feat(modes): sky shoot round logic`.

## Task 10A: WordJudge – chấm từ nói

**Files:** Create `lib/speech/word_judge.dart`; Test `test/speech/word_judge_test.dart`.

**Interfaces:**
- Produces:
  - `class RecognitionResult { final List<String> transcripts; final List<double>? confidences; }` (`transcripts[0]` là kết quả tốt nhất)
  - `class WordJudge { static bool matches(RecognitionResult r, ContentItem item, {double minConfidence = 0.3}); static String normalize(String s); }` — `normalize` hạ chữ thường, bỏ dấu câu, gộp khoảng trắng.

- [ ] **Step 1:** Test: `matches` đúng khi `transcripts == ['Hand.']` và `word == 'hand'`; đúng khi từ đích chỉ có ở kết quả thay thế thứ ba; đúng khi trùng một `spokenVariants` (ví dụ `word 'red'`, variants `['read']`); sai với `['hat']`; sai khi trùng nhưng `confidences == [0.1, ...]` cho đúng kết quả đó; `confidences == null` thì bỏ qua ngưỡng (đúng); `transcripts` rỗng → sai; `'a hand'` (có từ thừa) → sai; `normalize('  HAND!! ') == 'hand'`.
- [ ] **Step 2:** Chạy test, kỳ vọng FAIL. Cài. Chạy test, kỳ vọng PASS.
- [ ] **Step 3:** Commit `feat(speech): word judge`.

## Task 10B: Logic SayIt (mini-game đọc to)

**Files:** Create `lib/modes/say_it.dart`; Test `test/modes/say_it_test.dart`.

**Interfaces:**
- Consumes: `ContentItem`, `RecognitionResult`, `WordJudge` (Task 10A), `RoundResult` (Task 8).
- Produces:
  - `enum WordMotion { fallDown, rightToLeft }`
  - `enum WordPhase { running, judged, exploding, gone }`
  - `class SayItWord { final ContentItem item; final WordMotion motion; WordPhase phase; RoundResult? result; double progress; }` (`progress` 0..1 từ lúc xuất hiện tới đáy/mép trái)
  - `class SayItGame { SayItGame(List<ContentItem> items, {required Duration travelTime, required Random rng}); void tick(Duration dt); void onRecognized(RecognitionResult r); void onRecognitionFailed(); SayItWord get current; bool get finished; int get correctCount; List<SayItWord> get words; }`
  - Hằng: `const Duration kExplosionTime = Duration(milliseconds: 800);` `const Duration kJudgedHold = Duration(milliseconds: 700);`

- [ ] **Step 1:** Test (đồng hồ giả bằng `tick`): `SayItGame` ném `ArgumentError` nếu không đúng 3 mục; từ đầu `running` với `progress == 0`; `tick(travelTime/2)` → `progress == 0.5`; `onRecognized` khớp → `result == correct`, `phase == judged`; sau `kJudgedHold` → `exploding`, sau `kExplosionTime` nữa → `gone` và `current` là từ kế tiếp; `onRecognized` không khớp → `wrong`; `tick` đủ `travelTime` mà chưa có kết quả → `wrong` (mất từ) rồi cũng nổ và biến mất; `onRecognitionFailed` (lỗi nhận dạng hoặc không nghe thấy) chưa chốt kết quả, từ vẫn chạy; sau từ thứ ba `gone` → `finished == true`, `correctCount` đúng; `onRecognized` khi từ đang `judged`/`exploding` bị bỏ qua; với `Random(1)` cả hai giá trị `WordMotion` đều xuất hiện trong 20 ván.
- [ ] **Step 2:** Chạy test, kỳ vọng FAIL. Cài.
- [ ] **Step 3:** Chạy test, kỳ vọng PASS. Commit `feat(modes): say-it round logic`.

## Task 11: Tiến độ và lịch sử lưu cục bộ

**Files:** Create `lib/progress/progress_store.dart`; Test `test/progress/progress_store_test.dart`.

**Interfaces:**
- Produces: `class ProgressStore implements HistoryStore { ProgressStore(SharedPreferences prefs); int starsFor(int grade, int level); Future<void> saveStars(int grade, int level, int stars); bool isUnlocked(int grade, int level); }`. Level 1 luôn mở. `saveStars` chỉ ghi nếu cao hơn giá trị cũ. `recentIds()` giữ tối đa 200 id gần nhất.

- [ ] **Step 1:** Test với `SharedPreferences.setMockInitialValues({})`: ban đầu `isUnlocked(3,1)` true, `isUnlocked(3,2)` false; `saveStars(3,1,1)` mở level 2; `saveStars(3,1,3)` rồi `saveStars(3,1,1)` giữ 3; ghi 250 id còn 200 id mới nhất.
- [ ] **Step 2:** Chạy test, kỳ vọng FAIL. Cài. Chạy test, kỳ vọng PASS. Commit `feat(progress): local progress and history`.

## Task 12: TTS service

**Files:** Create `lib/audio/tts_service.dart`; Test `test/audio/tts_service_test.dart`.

**Interfaces:**
- Produces: `abstract class SpeechEngine { Future<bool> isEnglishAvailable(); Future<void> speak(String text); }`; `class TtsService { TtsService(SpeechEngine e); Future<bool> say(String text); }` — trả `false` (không ném lỗi) khi giọng tiếng Anh không có hoặc `speak` lỗi; có `FlutterTtsEngine` thật dùng ngôn ngữ `en-US`.

- [ ] **Step 1:** Test với `FakeEngine`: có giọng → `say('hand')` trả `true` và engine nhận `'hand'`; `isEnglishAvailable` false → trả `false`, engine không được gọi; engine ném lỗi → trả `false` (Review Focus).
- [ ] **Step 2:** Chạy test, kỳ vọng FAIL. Cài. Chạy test, kỳ vọng PASS. Commit `feat(audio): tts service with fallback`.

## Task 13: MediaPipe Pose thật (Android)

**Files:** Create `lib/input/mediapipe_pose_source.dart`, `android/` quyền camera; Test `test/input/pose_session_test.dart` (dùng `MockPoseSource`).

**Interfaces:**
- Consumes: `PoseEventSource`, `JumpDetector`, `laneFor`, `PullDetector`, `Calibration`.
- Produces: `class PoseSession implements PoseEventSource { PoseSession(Stream<Pose> poses, {int laneCount = 3}); }` — biến luồng `Pose` thành sự kiện; chỉ theo dõi người đã hiệu chỉnh (chọn người có `torsoHeight` lớn nhất lúc hiệu chỉnh, bỏ qua pose khác lệch `centerX` quá 0,25 — Review Focus); mất pose liên tục 500 ms phát `PlayerLost`, có lại phát `PlayerFound`. `MediapipePoseSource` bọc plugin và phát `Pose`.

- [ ] **Step 1:** Test `PoseSession` với luồng `Pose` ghi sẵn: nhảy → `Jumped`; bước sang làn khác → `LaneChanged`; không có pose 600 ms → `PlayerLost`; thêm người thứ hai cách xa không sinh sự kiện; quyền camera bị từ chối → `calibrate()` trả `null` và phát lỗi `CameraPermissionDenied` (Review Focus).
- [ ] **Step 2:** Chạy test, kỳ vọng FAIL. Cài `PoseSession` và `MediapipePoseSource` (xin quyền camera, CameraX).
- [ ] **Step 3:** Chạy test, kỳ vọng PASS. Cài bản debug lên S24 Ultra và xác nhận log sự kiện khi nhảy/bước.
- [ ] **Step 4:** Commit `feat(input): pose session and mediapipe source`.

## Task 13A: Nhận dạng giọng nói Android

**Files:** Create `lib/speech/speech_source.dart`, `lib/speech/android_speech_source.dart`, `android/app/src/main/AndroidManifest.xml` (quyền `RECORD_AUDIO`, khai báo `<queries>` cho dịch vụ nhận dạng); Test `test/speech/speech_session_test.dart`.

**Interfaces:**
- Consumes: `RecognitionResult` (Task 10A), `TtsService` (Task 12).
- Produces:
  - `abstract class SpeechSource { Future<SpeechAvailability> check(); Stream<RecognitionResult> listen({Duration maxListen = const Duration(seconds: 6)}); Future<void> stop(); }`
  - `enum SpeechAvailability { available, noPermission, noService, noEnglish }`
  - `class SpeechSession { SpeechSession(SpeechSource s, AudioDucker ducker); Stream<RecognitionResult> listenForWord(); }` — gọi `ducker.mute()` trước khi nghe và `ducker.restore()` sau khi xong hoặc lỗi; `abstract class AudioDucker { void mute(); void restore(); }`
  - `class AndroidSpeechSource implements SpeechSource` — dùng `SpeechRecognizer` `en-US` với kết quả thay thế và điểm tin cậy; ưu tiên bộ trên máy khi `isOnDeviceRecognitionAvailable` (API 31+), bắt `UnsupportedOperationException`; gói plugin Flutter hiện có (ví dụ `speech_to_text`) nếu đủ top-N và điểm tin cậy, nếu không thì viết kênh nền Kotlin.

- [ ] **Step 1:** Test `SpeechSession` với `FakeSpeechSource` và `FakeDucker`: gọi `listenForWord` thì `mute` được gọi trước khi nguồn bắt đầu nghe và `restore` được gọi khi luồng kết thúc; nguồn ném lỗi → `restore` vẫn được gọi và lỗi được chuyển thành sự kiện lỗi, không crash; `check()` trả `noPermission`/`noService` → `SpeechSession` báo không khả dụng để UI ẩn SayIt (Review Focus).
- [ ] **Step 2:** Chạy test, kỳ vọng FAIL. Cài `SpeechSession` và `AndroidSpeechSource`.
- [ ] **Step 3:** Chạy test, kỳ vọng PASS. Cài bản debug lên S24 Ultra, đọc thử 5 từ và xác nhận kết quả về đúng, nhạc nền tắt trong lúc nghe.
- [ ] **Step 4:** Commit `feat(speech): android recognizer and session`.

## Task 14: Nội dung lớp 1–5

**Files:** Create `assets/content/grade{1..5}/u<NN>.json` theo `docs/content/unit-map.md`; Test `test/content/content_validity_test.dart`.

**Interfaces:**
- Consumes: schema ở Task 5, bảng unit ở `unit-map.md`.

- [ ] **Step 1:** Test duyệt mọi file JSON: `id` duy nhất toàn cục; mỗi unit >= 8 mục (để pool level 1 >= 16 khi gộp 2 unit); mỗi mục có >= 2 `distractors` khác `word`; mục chỉ có `dragSpell` thì `word` dài >= 3 chữ cái; lớp 1–2 chỉ dùng `laneJump` và `sayIt`; lớp 3–5 có ít nhất một mục `dragSpell` và `skyShoot` mỗi unit; mỗi unit có >= 4 mục `sayIt` (từ đơn, không dấu câu), và lớp 1–2 chỉ cho `sayIt` với từ <= 2 âm tiết; `spokenVariants` (nếu có) khác `word` và đã chuẩn hóa. Điền `spokenVariants` từ kết quả spike ở Task 0.
- [ ] **Step 2:** Chạy test, kỳ vọng FAIL (chưa có dữ liệu). Soạn từng lớp theo thứ tự lớp 3, 4, 5, 1, 2; mỗi lớp một commit.
- [ ] **Step 3:** Chạy test, kỳ vọng PASS. Nhờ giáo viên hoặc chủ dự án rà từ vựng với sách thật.

## Task 15: Giao diện Flame và mascot (sau khi chọn phương án đồ họa)

**Files:** Create `lib/ui/theme/theme.dart`, `lib/ui/mascot/tin_tin.dart`, `lib/ui/screens/{home,lane_jump,drag_spell,sky_shoot,result}_screen.dart`; Test `test/ui/screens_test.dart`.

**Interfaces:**
- Consumes: các `*Round` của Task 8–10, `PoseSession`, `QuestionGenerator`, `ProgressStore`, `TtsService`.
- Produces: `class AppTheme` chứa token màu/font của phương án đã chọn (xem canvas thiết kế); `enum TinTinState { idle, happy, sad, cheer, dance }`.

**Điều kiện bắt đầu:** người dùng chọn một trong ba phương án (A Khu vườn mây, B Phi hành đoàn, C Kẹo giấy) và cung cấp mascot Tin Tin thật.

- [ ] **Step 1:** Widget test mỗi màn hình dùng `MockPoseSource`: `HomeScreen` có nút Play và chọn lớp, và chỉ hiện mục SayIt khi `SpeechAvailability.available`; `LaneJumpScreen` hiện 3–4 làn, `Jumped` ở làn đúng hiện `TinTinState.happy`; `SkyShootScreen` hiện số lượt bắn còn lại; `SayItScreen` (dùng `FakeSpeechSource`) hiện từ đang chạy theo `WordMotion`, hiện nhãn "Đúng"/"Sai" khi `judged`, hiệu ứng nổ khi `exploding`, và không còn widget của từ khi `gone`; `ResultScreen` hiện đúng số sao theo `Scoring.stars`.
- [ ] **Step 2:** Chạy test, kỳ vọng FAIL. Cài màn hình với token của phương án chọn; hiệu ứng ngắn dưới 1,5 giây (nhún chữ, pháo hoa sao, Tin Tin nhảy múa).
- [ ] **Step 3:** Cài khung chung: màn hiệu chỉnh đầu phiên, tạm dừng khi `PlayerLost`, tạm dừng khi ứng dụng xuống nền (`AppLifecycleState.paused`, Review Focus), banner quảng cáo nhỏ ở góc.
- [ ] **Step 4:** Chạy test, kỳ vọng PASS. Commit `feat(ui): screens, mascot, theme`.

## Task 16: Kiểm thử thiết bị và phát hành thử

**Files:** Create `docs/superpowers/notes/device-qa.md`, `.github/workflows/ci.yml`.

- [ ] **Step 1:** CI chạy `flutter analyze` và `flutter test` cho mỗi PR.
- [ ] **Step 2:** Chơi đủ 5 level ở cả ba mode trên S24 Ultra, qua cast/HDMI lên TV; ghi lỗi vào `device-qa.md` (độ trễ nhảy, nhận làn, đọc chữ từ 2–3 m).
- [ ] **Step 3:** Sửa lỗi tìm được, lặp lại tới khi hết lỗi chặn; build APK để cài thử.
- [ ] **Step 4:** Commit `docs: device qa notes`.

## Self-review

- **Độ phủ spec:** điều khiển (Task 2–4, 13), ba mode (8–10, 15), SayIt (10A, 10B, 13A, 15), nội dung (5, 14), random hóa (7), level/điểm (6, 11), kiến trúc/lỗi (13, 15), TTS (12), đồ họa/animation (15), repo (Global Constraints).
- **Nhất quán kiểu:** `RoundResult`, `ModeKind`, `LevelConfig`, `HoldProgress` được định nghĩa một lần và dùng nhất quán ở các task sau.
- **Thay đổi nhỏ so với spec:** `JumpDetector` phát sự kiện ngay khi vượt ngưỡng (độ trễ thấp) và chỉ nạp lại khi người chơi hạ xuống; spec viết "rồi hạ xuống", ý là điều kiện nạp lại.
- **Phụ thuộc:** Task 0 quyết định ngưỡng cho Task 3; Task 5 bước 4 tạo `unit-map.md` cho Task 14; Task 15 chờ người dùng chọn phương án đồ họa.
