# Tin Tin English (Motion English Game) Implementation Plan – v2

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Game Flutter/Flame học tiếng Anh tiểu học (lớp 1–5, Global Success) điều khiển bằng chuyển động qua camera điện thoại, chiếu lên TV; có mini-game đọc to nhận dạng giọng nói trên máy.

**Architecture:** Logic viết bằng Dart thuần, test được không cần camera/micro: input (pose → sự kiện), `Round` cho từng chế độ, `LevelSession` điều phối lượt chơi, content/levels/progress. Camera (MediaPipe) và nhận dạng giọng nói nằm sau giao diện nguồn, thay bằng nguồn giả và chuỗi landmark ghi thật từ spike. Làm theo pha: Pha 1 là một lát cắt dọc chơi được trên TV (LaneJump lớp 1) trước khi mở rộng.

**Tech Stack:** Flutter stable (ghim phiên bản ở Task 1), Dart, Flame, MediaPipe Pose Landmarker (Android; plugin hoặc kênh Kotlin, chốt ở Task 0), bộ nhận dạng giọng nói trên máy (chốt ở Task 0), `flutter_tts`, `just_audio`, `shared_preferences`, `wakelock_plus`, `flutter_test`.

**Spec:** `docs/superpowers/specs/2026-11-01-motion-english-game-design.md` (v2)

## Global Constraints

- Android trước; kiểm thử trên Galaxy S24 Ultra (Android 17) và một máy tầm trung đời 2021–2022. Khóa ngang, giữ màn hình sáng khi chơi.
- Camera và micro chỉ xử lý trên máy, không lưu, không gửi. Ngoài `lib/ads/`, không file nào import thư viện mạng.
- Pose: tối đa 2 người mỗi khung; chọn người đứng yên gần tâm khung trong 2 giây hiệu chỉnh rồi bám theo; mất pose quá 500 ms phát `PlayerLost`.
- Nhảy: độ nâng trung bình (hông giữa, vai giữa) ≥ 12% chiều cao thân; phát ngay khi vượt ngưỡng; nạp lại khi hạ dưới nửa ngưỡng và qua 600 ms; bỏ qua 500 ms đầu mỗi câu và khung đầu sau `PlayerFound`. Chế độ không nhảy: giơ hai tay quá đầu 0,5 giây.
- Làn: bề rộng = 0,6 × chiều cao thân; vùng trễ 10% bề rộng làn; lật trục x với camera trước; làn chốt là làn trước lúc bật nhảy.
- Giữ: 1 giây; rời mục tiêu dưới 200 ms không mất tiến độ. Kéo dây: 4 lần, hai tay luân phiên. SkyShoot: 3 lượt bắn; đồng hồ dừng khi đã trúng; chấm trúng theo vị trí mũi tên tại thời điểm khung pose trừ độ trễ cast đã đo.
- Không chắc thì không chấm: đầu vào không đáng tin thì bỏ qua, không báo "Sai".
- Bảng level (spec mục 5): câu 8/10/10/12/12; giây cơ bản 20/18/15/12/10; đáp án 3/3/4/4/4; gợi ý full/full/partial/none/none; unit: đang học / +1 trước / +2 trước / mọi unit đã học / mọi unit đã học. Thời gian: LaneJump = cơ bản; SkyShoot = cơ bản × 1,5; DragSpell = cơ bản + 3 giây × số ô; SayIt = cơ bản (thời gian từ chạy hết màn hình). Đồng hồ chỉ chạy sau khi đọc xong câu hỏi.
- 100 điểm mỗi câu đúng. Sao bằng số nguyên: `correct*100 >= 90*total` → 3, `>= 75*total` → 2, `>= 50*total` → 1. SayIt (9 từ): ≥ 8 → 3, ≥ 7 → 2, ≥ 5 → 1. Mở khóa level N+1 khi level N ≥ 1 sao. Câu ôn tập không tính điểm/sao.
- Random: pool theo cặp (mục × dạng hỏi), mục tiêu ≥ 2 × số câu, thiếu thì lặp sau khi hết pool; đáp án đúng không cùng vị trí quá 2 câu liên tiếp; lịch sử 200 mục; mục sai ưu tiên cao nhất, tối đa 30% số câu, không ở câu đầu, gỡ khi trả lời đúng.
- SayIt: 3 từ chạy lần lượt mỗi ván, 3 ván mỗi level; rơi xuống hoặc phải sang trái (ngẫu nhiên); có kết quả thì hiện Đúng/Sai 700 ms rồi nổ 800 ms và biến mất; chạy hết mà chưa có kết quả là sai; kết quả muộn tối đa 1 giây vẫn tính; tự mở lại micro khi bộ nhận dạng dừng; tắt nhạc/hiệu ứng khi nghe; chuẩn hóa (chữ thường, bỏ dấu câu, gạch nối → khoảng trắng, số 0–100 → chữ, bỏ a/an/the đầu); tin cậy ≥ 0,3 chỉ khi giá trị > 0; lớp 1–2 đọc mẫu trước và chỉ từ ≤ 2 âm tiết.
- Quảng cáo: SDK chứng nhận Families, hướng tới trẻ em, không cá nhân hóa, mức G, chỉ banner góc, không hiện ở màn hiệu chỉnh, cảnh báo, khu vực phụ huynh.
- Repo `avdoremon/g_english_motion`; package `g_english_motion`. Nội dung tự soạn, không sao chép văn bản sách.

## Review Focus

- **Báo "Sai" oan vì đầu vào không chắc chắn** (pose tin cậy thấp đúng lúc nhảy, làn đang dao động, kết quả giọng nói về muộn sang từ sau): phải bỏ qua và chờ, không chấm. Test ở Task 5 (`Confirmed` bị chặn khi tin cậy thấp), Task 10 (Round bỏ qua khi `PlayerLost`), Task 22 (kết quả gắn sai từ bị bỏ).
- **Độ trễ cast làm SkyShoot chấm trượt trong khi bé thấy trúng:** chấm theo thời điểm khung pose trừ độ trễ. Test ở Task 19.
- **Người thứ hai vào khung hoặc đứng gần camera hơn bé:** vẫn bám đúng bé. Test ở Task 5.
- **Giọng hoặc hình của trẻ rời khỏi máy:** không thư viện mạng ngoài `lib/ads/`; SayIt chỉ chạy với bộ nhận dạng trên máy. Test kiến trúc ở Task 1, test ở Task 21.
- **Bé lớp 1–2 chưa biết đọc gặp lúc TTS hỏng, mất người, hoặc app xuống nền:** phát lời thu sẵn, đồng hồ tạm dừng, không mất câu. Test ở Task 11 và Task 12.

---

## File Structure

```
lib/
  input/     pose_types.dart, game_input_event.dart, one_euro_filter.dart, calibrator.dart,
             jump_detector.dart, raise_hands_detector.dart, lane_tracker.dart,
             cursor_tracker.dart, hold_tracker.dart, pull_detector.dart,
             pose_session.dart, pose_frame_source.dart, mediapipe_frame_source.dart
  modes/     round.dart, lane_jump.dart, drag_spell.dart, sky_shoot.dart, say_it.dart
  session/   level_session.dart
  content/   models.dart, content_repository.dart, curriculum.dart, history_store.dart,
             question_models.dart, question_generator.dart
  levels/    level_config.dart, scoring.dart
  audio/     audio_service.dart, voice_lines.dart
  speech/    word_judge.dart, speech_source.dart, speech_session.dart, on_device_speech_source.dart
  progress/  progress_store.dart
  ads/       ads_config.dart, corner_banner.dart
  ui/        shell/, parent/, screens/, mascot/, theme/
assets/  config/levels.json, content/grade1..5/*.json, images/, audio/vi/, audio/en/
test/    phản chiếu lib/; test/fixtures/landmarks/*.json (ghi từ spike)
```

# Pha 1 – Lát cắt dọc: LaneJump lớp 1 chơi được trên TV

## Task 0: Spike đo đạc (vứt mã, giữ số liệu và fixture)

**Files:** `spike/` (không merge), `docs/superpowers/notes/spike-results.md`, `test/fixtures/landmarks/*.json` (giữ lại)

**Interfaces:** Produces: ngưỡng chốt cho Global Constraints; độ trễ cast `castLatencyMs` theo từng cách chiếu; lựa chọn nguồn pose và bộ nhận dạng giọng nói; chuỗi landmark thật cho test.

- [ ] **Step 1:** App tối thiểu: camera + pose (`numPoses = 2`) + vẽ một ô đổi màu khi phát hiện nhảy; ghi landmark mỗi khung ra JSON.
- [ ] **Step 2:** Đo trên S24 Ultra và máy tầm trung, với một bé 6–7 tuổi và một bé 9–10 tuổi (bắt buộc), ở 2 m và 3 m, phòng sáng và tối: nhảy 20 lần, bước 3–4 làn, giữ cổ tay 1 giây trên ô cỡ dự kiến, 4 lần kéo dây, giơ hai tay. Ghi bỏ sót, báo nhầm.
- [ ] **Step 3:** Đo độ trễ "chân rời đất → ô đổi màu trên TV" bằng video 60 fps quay cả bé và TV, qua Smart View, Chromecast và HDMI.
- [ ] **Step 4:** Chạy 20 phút liền mỗi máy với mirroring: ghi fps suy luận và nhiệt độ.
- [ ] **Step 5:** So sánh nguồn pose: plugin `flutter_mp_pose_landmarker` và kênh Kotlin trên MediaPipe Tasks Vision chính thức. Tiêu chí: hỗ trợ `numPoses`, GPU delegate, xoay ảnh, chọn camera trước/sau, còn bảo trì.
- [ ] **Step 6:** Spike giọng nói, chỉ bộ nhận dạng trên máy: (a) Android `createOnDeviceSpeechRecognizer` khi `isOnDeviceRecognitionAvailable`; (b) một bộ offline nhúng giới hạn từ vựng (ví dụ Vosk với từ đích + từ nhiễu). 10 từ lớp 3, mỗi từ 5 lần mỗi người, ở 0,5–1 m, TV tắt và bật tiếng, chế độ máy bay. Ghi tỉ lệ đúng top-N, và các biến thể sai lặp lại (cho `spokenVariants`).
- [ ] **Step 7:** Ghi kết quả và quyết định vào notes. Tiêu chí qua: bỏ sót nhảy ≤ 10%, báo nhầm ≤ 5%, độ trễ đến TV ≤ 350 ms trên ít nhất một cách chiếu, suy luận ≥ 20 fps sau 20 phút trên máy tầm trung; giọng nói ≥ 80% top-N với người lớn và ≥ 60% với bé. Không đạt phần nhảy thì đặt chế độ không nhảy (giơ hai tay) làm mặc định; không đạt phần giọng nói thì SayIt chuyển sang pha sau và hỏi lại người dùng. Cập nhật Global Constraints.
- [ ] **Step 8:** Lưu tối thiểu 6 chuỗi landmark (nhảy, bước làn, hai người, mất người, giơ tay, kéo dây) vào `test/fixtures/landmarks/`. Không commit video; xóa video có trẻ sau khi đo. Commit notes + fixtures.

## Task 1: Khởi tạo dự án và kiểm tra kiến trúc

**Files:** Create `pubspec.yaml`, `analysis_options.yaml`, `lib/main.dart`, `test/smoke_test.dart`, `test/architecture_test.dart`, `.github/workflows/ci.yml`, `.gitignore`; Modify `README.md`.

**Interfaces:** Produces: `GEnglishMotionApp`; CI chạy `flutter analyze` và `flutter test`.

- [ ] **Step 1:** Test `smoke_test.dart`: pump `GEnglishMotionApp`, `expect(find.text('Tin Tin English'), findsOneWidget)`.
- [ ] **Step 2:** Test `architecture_test.dart`: quét mọi file `lib/**/*.dart` ngoài `lib/ads/`; không file nào chứa `package:http`, `package:dio`, `dart:io` kèm `HttpClient`, hay `WebSocket`. Thêm một file vi phạm tạm để chắc test bắt được, rồi xóa.
- [ ] **Step 3:** Chạy test, kỳ vọng FAIL.
- [ ] **Step 4:** `flutter create --org vn.avdoremon --platforms android .`; ghim Flutter stable trong README và `environment`; thêm phụ thuộc ở Tech Stack; khóa ngang trong `main.dart`.
- [ ] **Step 5:** `flutter analyze && flutter test` PASS; thêm CI. Commit `feat: scaffold app, ci, architecture test`.

## Task 2: Kiểu pose, sự kiện, bộ lọc

**Files:** Create `lib/input/pose_types.dart`, `game_input_event.dart`, `one_euro_filter.dart`; Test `test/input/one_euro_filter_test.dart`.

**Interfaces:**
- Produces:
  - `enum PoseJoint { nose, leftShoulder, rightShoulder, leftHip, rightHip, leftWrist, rightWrist, leftKnee, rightKnee }`
  - `class Landmark { final double x, y, confidence; }` (chuẩn hóa 0..1, y hướng xuống)
  - `class Pose { final Map<PoseJoint, Landmark> joints; double? midHipY; double? midHipX; double? midShoulderY; double? torsoHeight; }` (getter trả `null` nếu thiếu khớp hoặc confidence < 0.5)
  - `class PoseFrame { final List<Pose> poses; final Duration timestamp; }`
  - `enum Hand { left, right }`
  - `sealed class GameInputEvent { final Duration at; }`: `LaneChanged(int lane)`, `Confirmed(int lane)`, `CursorMoved(double x, double y)`, `Pulled(Hand hand)`, `PlayerLost()`, `PlayerFound()`
  - `class OneEuroFilter { OneEuroFilter({double minCutoff = 1.0, double beta = 0.01}); double filter(double value, Duration t); void reset(); }`

- [ ] **Step 1:** Test: giá trị hằng 0.5 → đầu ra 0.5; nhiễu ±0.02 quanh 0.5 → biên độ đầu ra < 0.01; bước nhảy 0.5 → 0.6 → đầu ra đạt > 0.59 trong 200 ms ở 30 fps; test `Pose.torsoHeight` = 0.3 với vai 0.3, hông 0.6, và `null` khi `leftHip` confidence 0.3.
- [ ] **Step 2:** FAIL → cài → PASS. Commit `feat(input): pose types, events, filter`.

## Task 3: Calibrator, JumpDetector, RaiseHandsDetector

**Files:** Create `lib/input/calibrator.dart`, `jump_detector.dart`, `raise_hands_detector.dart`; Test tương ứng trong `test/input/`.

**Interfaces:**
- Consumes: `Pose`, `PoseFrame`, `OneEuroFilter`.
- Produces:
  - `class Calibration { final double torsoHeight, centerX, baselineHipY, baselineShoulderY; }`
  - `enum CalibrationIssue { noPerson, notStill, tooClose, notCentered }`
  - `class CalibrationProgress { final double progress; final Calibration? result; final CalibrationIssue? issue; final int? selectedPoseIndex; }`
  - `class Calibrator { Calibrator({Duration hold = const Duration(seconds: 2)}); CalibrationProgress add(PoseFrame f); }` — chọn pose có `|midHipX − 0.5|` nhỏ nhất trong số pose đứng yên (dao động `midHipY` < 0.02 × thân); `tooClose` khi thiếu `nose` hoặc đầu gối, hoặc `nose.y < 0.08`.
  - `class JumpDetector { JumpDetector(Calibration c, {double threshold = 0.12, Duration debounce = const Duration(milliseconds: 600)}); bool update(Pose p, Duration t); void suppressUntil(Duration t); }` — mốc chuẩn cập nhật EMA khi bé đứng yên ≥ 1 giây.
  - `class RaiseHandsDetector { RaiseHandsDetector({Duration hold = const Duration(milliseconds: 500)}); bool update(Pose p, Duration t); }` — hai cổ tay cao hơn `nose`; phát một lần, nạp lại khi hạ tay.

- [ ] **Step 1:** Test Calibrator: 60 khung đứng yên ở 30 fps → `result` có `torsoHeight` ≈ 0.3 (±0.005), `progress` = 1; dao động mạnh → `notStill`, chưa có `result`; hai pose (x = 0.5 và x = 0.8) đều đứng yên → `selectedPoseIndex` là pose ở 0.5; thiếu đầu gối → `tooClose`; dùng fixture thật "đứng yên" từ Task 0 → có `result`.
- [ ] **Step 2:** Test JumpDetector (thân 0.3, ngưỡng nâng 0.036): nâng 0.04 → `true` đúng một lần; vẫn ở trên cao khi hết debounce → `false`; hạ xuống rồi nhảy lại sau 300 ms → `false`; sau 700 ms → `true`; nâng 0.02 → `false`; `suppressUntil(t+500ms)` chặn nhảy trong khoảng đó; bé lùi xa dần (thân giảm 0.3 → 0.25 chậm trong 5 giây, không nhảy) → không `true`; fixture thật "nhảy 10 lần" → đúng 10 lần ±1.
- [ ] **Step 3:** Test RaiseHandsDetector: hai tay cao hơn mũi 500 ms → `true` một lần; 400 ms → `false`; một tay → `false`; hạ rồi giơ lại → `true` lần nữa.
- [ ] **Step 4:** FAIL → cài → PASS. Commit `feat(input): calibrator, jump and raise-hands detectors`.

## Task 4: LaneTracker

**Files:** Create `lib/input/lane_tracker.dart`; Test `test/input/lane_tracker_test.dart`.

**Interfaces:**
- Consumes: `Calibration`, `Pose`.
- Produces: `class LaneTracker { LaneTracker(Calibration c, {required int laneCount, bool mirror = true, double hysteresis = 0.1}); int update(Pose p, Duration t); int get current; int laneAt(Duration t); void setLaneCount(int n); }` — bề rộng làn = 0.6 × `torsoHeight`; các làn đặt đối xứng quanh `centerX`; `laneAt` tra lịch sử 1 giây gần nhất.

- [ ] **Step 1:** Test (thân 0.3 → bề rộng 0.18, center 0.5, 3 làn, `mirror: false`): x 0.5 → 1; 0.30 → 0; 0.70 → 2; 0.0 → 0; 1.0 → 2. Với 4 làn: x 0.41 → 1, 0.59 → 2. Vùng trễ: từ làn 1 dịch tới đúng ranh +0.01 → vẫn 1; tới ranh +0.03 → 2. `mirror: true`: x 0.30 → 2. `laneAt(t − 200ms)` trả làn trước khi đổi. `setLaneCount(4)` đổi số làn mà không ném lỗi.
- [ ] **Step 2:** FAIL → cài → PASS. Commit `feat(input): lane tracker`.

## Task 5: PoseSession

**Files:** Create `lib/input/pose_session.dart`, `lib/input/pose_frame_source.dart`; Test `test/input/pose_session_test.dart`.

**Interfaces:**
- Consumes: Task 2–4.
- Produces:
  - `enum ConfirmGesture { jump, raiseHands }`
  - `enum PermissionOutcome { granted, denied, permanentlyDenied }`
  - `abstract class PoseFrameSource { Future<PermissionOutcome> start(); Stream<PoseFrame> get frames; Future<void> stop(); }`; `FakePoseFrameSource` phát từ fixture hoặc danh sách.
  - `class PoseSession { PoseSession(Stream<PoseFrame> frames, Calibration c, {required int laneCount, ConfirmGesture confirm = ConfirmGesture.jump, double minConfidence = 0.5}); Stream<GameInputEvent> get events; int get currentLane; void setLaneCount(int n); void suppressConfirmUntil(Duration t); Future<void> dispose(); }`
  - Bám người: mỗi khung chọn pose có `|midHipX − lastX| + |torsoHeight − lastTorso|` nhỏ nhất; bỏ khung nếu khoảng cách > 0.25.
  - `Confirmed.lane` = `laneTracker.laneAt(thời điểm bắt đầu nâng người)`; `Confirmed.at` = timestamp khung vượt ngưỡng.

- [ ] **Step 1:** Test với `FakePoseFrameSource`: nhảy → một `Confirmed(lane: 1)` có `at` bằng timestamp khung; bước sang phải → `LaneChanged(2)`; bước rồi nhảy và hông dạt sang làn khác lúc bay → `Confirmed.lane` vẫn là làn trước lúc nhảy; không pose 600 ms → `PlayerLost`, có lại → `PlayerFound`, và khung đầu sau đó không sinh `Confirmed`; người thứ hai xuất hiện ở x = 0.85 và đứng gần camera hơn (thân 0.45) → không sự kiện nào từ người đó; fixture "hai người" từ Task 0 → chỉ sự kiện của bé; khung có confidence hông 0.3 đúng lúc vượt ngưỡng → không `Confirmed` (Review Focus); `ConfirmGesture.raiseHands` → giơ tay sinh `Confirmed`, nhảy thì không.
- [ ] **Step 2:** FAIL → cài → PASS. Commit `feat(input): pose session with player tracking`.

## Task 6: Nguồn khung hình MediaPipe (Android)

**Files:** Create `lib/input/mediapipe_frame_source.dart`, phần native theo quyết định Task 0 (`android/app/src/main/kotlin/.../PoseChannel.kt` nếu tự viết kênh); Modify `AndroidManifest.xml` (quyền `CAMERA`); Test `test/input/mediapipe_frame_source_test.dart` (mock MethodChannel/EventChannel).

**Interfaces:**
- Consumes: `PoseFrameSource`, `PoseFrame`, `PermissionOutcome`.
- Produces: `class MediapipeFrameSource implements PoseFrameSource` — `numPoses = 2`, camera trước mặc định, timestamp lấy từ khung camera; không lưu khung hình.

- [ ] **Step 1:** Test với channel giả: payload landmark → `PoseFrame` đúng tọa độ và timestamp; quyền bị từ chối → `start()` trả `denied`, từ chối vĩnh viễn → `permanentlyDenied`, không ném lỗi.
- [ ] **Step 2:** FAIL → cài → PASS.
- [ ] **Step 3:** Cài bản debug lên S24 Ultra và máy tầm trung; log sự kiện `PoseSession` khi nhảy và bước làn; khớp kết quả spike.
- [ ] **Step 4:** Commit `feat(input): mediapipe frame source`.

## Task 7: Nội dung, curriculum, cấu hình level

**Files:** Create `lib/content/models.dart`, `content_repository.dart`, `curriculum.dart`, `lib/levels/level_config.dart`, `assets/config/levels.json`, `docs/content/unit-map.md`; Test `test/content/content_repository_test.dart`, `test/content/curriculum_test.dart`, `test/levels/level_config_test.dart`.

**Interfaces:**
- Produces:
  - `enum ModeKind { laneJump, dragSpell, skyShoot, sayIt }`
  - `class ContentItem { final String id, word, ttsText; final String? image; final int syllables; final List<String> sentencePatterns, distractorIds, spokenVariants; final List<ModeKind> modes; }`
  - `class Unit { final int grade, index; final String id, title; final List<ContentItem> items; }`
  - `class ContentRepository { ContentRepository(List<Unit> units); static Future<ContentRepository> loadFromAssets(AssetBundle b); List<Unit> unitsFor(int grade); ContentItem byId(String id); }` — ném `FormatException` kèm tên file khi JSON sai; ném khi `distractorIds` trỏ tới id không tồn tại.
  - `class CurriculumPosition { final int grade, currentUnitIndex; }`
  - `enum UnitWindow { current, currentPlus1, currentPlus2, allLearned }`
  - `List<Unit> unitsForLevel(ContentRepository r, CurriculumPosition p, UnitWindow w)` (trong `curriculum.dart`)
  - `enum HintMode { full, partial, none }`
  - `class LevelConfig { final int level, questionCount, choiceCount; final Duration baseTime; final HintMode hints; final UnitWindow window; static Future<List<LevelConfig>> load(AssetBundle b); }`

- [ ] **Step 1:** Test repository: nạp JSON mẫu `{"grade":1,"unit":"u01","index":1,"title":"...","items":[{"id":"g1u01-ball","word":"ball","ttsText":"ball","image":"ball.png","syllables":1,"distractorIds":["g1u01-bag"],"modes":["laneJump","sayIt"]}, ...]}` → `byId('g1u01-ball').word == 'ball'`; thiếu `id` → `FormatException` chứa tên file; `distractorIds` trỏ id lạ → lỗi.
- [ ] **Step 2:** Test curriculum: đang học unit 3 → `current` = [u03]; `currentPlus1` = [u02, u03]; `currentPlus2` = [u01, u02, u03]; đang học unit 1 với `currentPlus2` → [u01]; `allLearned` = u01..u03.
- [ ] **Step 3:** Test level config: `levels.json` có đúng 5 mục với giá trị của Global Constraints; level 1: `questionCount 8`, `baseTime 20s`, `choiceCount 3`, `hints full`, `window current`; level 5: `12`, `10s`, `4`, `none`, `allLearned`.
- [ ] **Step 4:** FAIL → cài → PASS.
- [ ] **Step 5:** Đối chiếu mục lục chính thức Global Success lớp 1–5 và ghi `docs/content/unit-map.md` (grade, index, title, chủ đề). Đây là nguồn cho mọi task nội dung. Commit `feat(content): models, curriculum, level config, unit map`.

## Task 8: Scoring và thời gian câu

**Files:** Create `lib/levels/scoring.dart`; Test `test/levels/scoring_test.dart`.

**Interfaces:**
- Consumes: `LevelConfig`, `ModeKind`.
- Produces: `class Scoring { static int points(int correct); static int stars(int correct, int total); static int sayItStars(int correctOfNine); static bool unlocksNext(int stars); static Duration timeFor(LevelConfig c, ModeKind m, {int slots = 0}); }`

- [ ] **Step 1:** Test: `stars(4,8)` = 1; `stars(3,8)` = 0; `stars(6,8)` = 2; `stars(9,10)` = 3; `stars(7,10)` = 1; `stars(0,0)` = 0; `sayItStars` 4 → 0, 5 → 1, 7 → 2, 8 → 3; `points(7)` = 700; `timeFor(level3, skyShoot)` = 22,5 s; `timeFor(level5, dragSpell, slots: 6)` = 28 s; `timeFor(level1, laneJump)` = 20 s.
- [ ] **Step 2:** FAIL → cài → PASS. Commit `feat(levels): scoring and timing`.

## Task 9: Mô hình câu hỏi và QuestionGenerator

**Files:** Create `lib/content/question_models.dart`, `history_store.dart`, `question_generator.dart`; Test `test/content/question_generator_test.dart`.

**Interfaces:**
- Consumes: Task 7.
- Produces:
  - `enum QuestionForm { listenPickPicture, seePicturePickWord, listenPickWord, fillBlank, spellWord, orderSentence }`
  - `class ChoiceOption { final String itemId; final bool showPicture; final bool showWord; }`
  - `sealed class Question { String get itemId; String get ttsText; QuestionForm get form; }`: `ChoiceQuestion({itemId, form, ttsText, String? promptText, String? promptImageItemId, List<ChoiceOption> choices, int correctIndex})`, `SpellQuestion({itemId, ttsText, String word, List<String> tiles, String? imageItemId})`, `OrderQuestion({itemId, ttsText, List<String> words, List<String> answer})`
  - `class PlannedQuestion { final ModeKind mode; final Question question; }`
  - `abstract class HistoryStore { List<String> recentIds(); Set<String> wrongIds(); Future<void> recordAsked(List<String> ids); Future<void> markWrong(String id); Future<void> clearWrong(String id); }`; `InMemoryHistoryStore`.
  - `class QuestionGenerator { QuestionGenerator(ContentRepository repo, HistoryStore history, Random rng); List<PlannedQuestion> plan({required LevelConfig level, required CurriculumPosition pos, required Set<ModeKind> modes}); List<ContentItem> sayItWords({required CurriculumPosition pos, required LevelConfig level, int count = 3, Set<String> exclude = const {}}); }`
  - Dạng hỏi theo mode: `laneJump` → `listenPickPicture`, `seePicturePickWord`, `listenPickWord`; `skyShoot` → `listenPickWord`, `fillBlank`; `dragSpell` → `spellWord`, `orderSentence`. Lớp 1–2 chỉ dạng có hình hoặc nghe.

- [ ] **Step 1:** Test với `Random(42)`: (a) không trùng `(itemId, form)` trong một lượt khi pool đủ; (b) qua 200 lượt, `correctIndex` không giống nhau quá 2 câu liên tiếp; (c) lượt 2 (sau `recordAsked` của lượt 1) có ≥ 70% cặp khác lượt 1 khi pool = 2 × số câu; (d) pool nhỏ hơn số câu → vẫn đủ `questionCount`, chỉ lặp sau khi dùng hết pool; (e) mỗi `ChoiceQuestion` có đúng `choiceCount` lựa chọn, không trùng đáp án đúng, nhiễu lấy từ `distractorIds` trước, thiếu thì lấy mục cùng lớp trong cửa sổ unit; (f) `SpellQuestion.tiles` là hoán vị của `word` và khác `word`; (g) 3 mục trong `wrongIds` với lượt 10 câu → cả 3 có mặt, không ở vị trí 0; 6 mục sai → tối đa 3 có mặt (30%); (h) `modes: {laneJump, dragSpell, skyShoot}` → lượt có cả ba mode; (i) lớp 1 không sinh `SpellQuestion`/`OrderQuestion`; (j) `sayItWords` lớp 1 chỉ trả mục `syllables <= 2` có mode `sayIt`, không trùng `exclude`.
- [ ] **Step 2:** FAIL → cài: chọn theo trọng số (sai gần đây có hạn mức > chưa hỏi gần đây > còn lại), xáo vị trí rồi sửa chuỗi trùng vị trí quá 2 bằng hoán vị cục bộ → PASS.
- [ ] **Step 3:** Commit `feat(content): question models and randomized generator`.

## Task 10: Round chung và LaneJump

**Files:** Create `lib/modes/round.dart`, `lib/modes/lane_jump.dart`; Test `test/modes/lane_jump_test.dart`.

**Interfaces:**
- Consumes: `ChoiceQuestion`, `GameInputEvent`.
- Produces:
  - `enum RoundResult { correct, wrong, timeout }`
  - `abstract class Round { void start(); void onEvent(GameInputEvent e); void tick(Duration dt); RoundResult? get result; int? get chosenIndex; Duration get remaining; bool get clockRunning; }` — `start()` được gọi khi đọc câu hỏi xong; trước đó đồng hồ không chạy và mọi `Confirmed` bị bỏ qua; sau `PlayerLost` đồng hồ dừng và sự kiện bị bỏ qua tới `PlayerFound`.
  - `class LaneJumpRound implements Round { LaneJumpRound(ChoiceQuestion q, {required Duration timeLimit, required int initialLane}); int get selectedLane; }`

- [ ] **Step 1:** Test: `initialLane 0`, `Confirmed(lane: 2)` với `correctIndex 2` sau `start()` → `correct`, `chosenIndex 2`; làn sai → `wrong`; `Confirmed` trước `start()` → bỏ qua; `tick` đủ `timeLimit` → `timeout`; `PlayerLost` rồi `tick(5s)` → `remaining` không đổi, `Confirmed` bị bỏ qua, `PlayerFound` → chạy tiếp; sau khi có `result`, sự kiện mới không đổi kết quả; `LaneChanged(1)` cập nhật `selectedLane`.
- [ ] **Step 2:** FAIL → cài → PASS. Commit `feat(modes): round contract and lane jump`.

## Task 11: LevelSession

**Files:** Create `lib/session/level_session.dart`; Test `test/session/level_session_test.dart`.

**Interfaces:**
- Consumes: `PlannedQuestion`, `Round`, `HistoryStore`, `Scoring`, `LevelConfig`.
- Produces:
  - `enum SessionPhase { prompting, playing, feedback, paused, finished }`
  - `class LevelOutcome { final int correct, total, points, stars; final bool unlockedNext; }`
  - `class LevelSession { LevelSession({required LevelConfig level, required List<PlannedQuestion> plan, required Round Function(PlannedQuestion pq, {required bool review}) makeRound, required HistoryStore history, Duration feedbackTime = const Duration(milliseconds: 2500)}); void begin(); void onPromptFinished(); void onEvent(GameInputEvent e); void tick(Duration dt); void pause(); void resume(); SessionPhase get phase; PlannedQuestion get current; bool get isReview; RoundResult? get lastResult; LevelOutcome? get outcome; }`
  - Luồng: `begin` → `prompting` (UI đọc câu hỏi) → `onPromptFinished` gọi `round.start()` → `playing` → có kết quả → `feedback` (UI phát khen/giải thích) → câu kế. Câu sai/hết giờ được thêm một lần vào cuối hàng đợi với `review: true` (không tính điểm/sao). Hết hàng đợi → `finished`, ghi `recordAsked`, `markWrong` cho câu sai lần đầu, `clearWrong` cho câu đúng.

- [ ] **Step 1:** Test với Round giả: 8 câu, đúng 6 → `outcome` có `correct 6`, `total 8`, `points 600`, `stars 2`; 2 câu sai được hỏi lại ở cuối với `isReview == true`, trả lời đúng ở lượt ôn không đổi `points`; `tick` trong `prompting` không giảm `remaining`; `pause()` (app xuống nền) → `tick(10s)` không đổi gì, `resume()` quay lại đúng pha trước (Review Focus); `history` nhận `recordAsked` với 8 id, `markWrong` 2 id, `clearWrong` 6 id; `unlockedNext` = true khi `stars >= 1`.
- [ ] **Step 2:** FAIL → cài → PASS. Commit `feat(session): level session orchestration`.

## Task 12: Âm thanh

**Files:** Create `lib/audio/audio_service.dart`, `lib/audio/voice_lines.dart`, `assets/audio/vi/*.m4a` (thu tạm bằng giọng người lớn), `assets/audio/en/<itemId>.m4a` cho từ lớp 1 của MVP; Test `test/audio/audio_service_test.dart`.

**Interfaces:**
- Produces:
  - `enum VoiceLine { welcome, standStill, stepBack, correct1, correct2, correct3, tryAgain, theAnswerIs, jumpToChoose, raiseHandsToChoose, pullTheRope, sayTheWord, levelComplete, takeABreak }` — mỗi dòng có file `assets/audio/vi/<name>.m4a` và phụ đề tiếng Việt.
  - `abstract class SpeechEngine { Future<bool> isEnglishAvailable(); Future<void> speak(String text); }`; `abstract class ClipPlayer { Future<bool> play(String assetPath); }`
  - `class AudioService { AudioService(SpeechEngine tts, ClipPlayer clips, {required bool Function(String path) assetExists}); Future<void> sayEnglish(String text, {String? itemId}); Future<void> playLine(VoiceLine l); Future<void> explainAnswer(ContentItem correct); Stream<String> get captions; void muteForListening(); void restoreAfterListening(); }` — `sayEnglish` ưu tiên file `assets/audio/en/<itemId>.m4a` nếu có, sau đó TTS, cuối cùng chỉ phụ đề; mọi lỗi nuốt lại, không ném; Future hoàn tất khi đọc xong (để gọi `onPromptFinished`).

- [ ] **Step 1:** Test với engine/player giả: có file `en/g1u01-ball.m4a` → phát file, không gọi TTS; không có file, TTS có giọng → gọi TTS; TTS không có giọng và không có file → không ném, `captions` vẫn phát "ball" (Review Focus); `explainAnswer` phát `theAnswerIs` rồi từ tiếng Anh, theo đúng thứ tự; `muteForListening` làm `ClipPlayer` nhạc nền dừng, `restoreAfterListening` phát lại.
- [ ] **Step 2:** FAIL → cài → PASS. Commit `feat(audio): audio service with recorded fallback and captions`.

## Task 13: ProgressStore và cài đặt phụ huynh

**Files:** Create `lib/progress/progress_store.dart`; Test `test/progress/progress_store_test.dart`.

**Interfaces:**
- Produces: `class ProgressStore implements HistoryStore { ProgressStore(SharedPreferences p); int starsFor(int grade, int level); Future<void> saveStars(int grade, int level, int stars); bool isUnlocked(int grade, int level); int currentUnit(int grade); Future<void> setCurrentUnit(int grade, int unitIndex); ConfirmGesture get confirmGesture; Future<void> setConfirmGesture(ConfirmGesture g); bool get sayItEnabled; Future<void> setSayItEnabled(bool v); bool get safetyAcknowledged; Future<void> acknowledgeSafety(); }`

- [ ] **Step 1:** Test với `SharedPreferences.setMockInitialValues({})`: level 1 mở, level 2 khóa; `saveStars(1,1,1)` mở level 2; `saveStars` không hạ sao; `currentUnit(1)` mặc định 1; `recentIds` giữ 200 id mới nhất khi ghi 250; `markWrong` rồi `clearWrong` → `wrongIds` rỗng; `confirmGesture` mặc định `jump`; `sayItEnabled` mặc định `true`; `safetyAcknowledged` mặc định `false`.
- [ ] **Step 2:** FAIL → cài → PASS. Commit `feat(progress): progress and parent settings`.

## Task 14: App shell và màn LaneJump

**Files:** Create `lib/ui/theme/app_theme.dart`, `lib/ui/mascot/tin_tin.dart`, `lib/ui/shell/{permission_screen,safety_screen,calibration_screen,pause_overlay,game_shell}.dart`, `lib/ui/parent/{parent_gate,parent_settings}.dart`, `lib/ui/screens/{home_screen,lane_jump_screen,result_screen}.dart`; Test `test/ui/shell_test.dart`, `test/ui/lane_jump_screen_test.dart`.

**Interfaces:**
- Consumes: `PoseFrameSource`, `Calibrator`, `PoseSession`, `QuestionGenerator`, `LevelSession`, `LaneJumpRound`, `AudioService`, `ProgressStore`.
- Produces: `class AppTheme` (token của phương án đồ họa được chọn; mặc định phương án B cho tới khi người dùng chọn); `enum TinTinState { idle, happy, sad, cheer, dance }`; `class GameShell` (giữ màn hình sáng khi chơi, tạm dừng `LevelSession` khi `AppLifecycleState.paused` hoặc `PlayerLost`).
- Mascot dùng hình tạm từ canvas thiết kế; thay hình thật sau mà không đổi code.

- [ ] **Step 1:** Widget test (nguồn giả): lần đầu mở → `SafetyScreen`, xác nhận xong → không hiện lại; quyền `permanentlyDenied` → `PermissionScreen` có nút "Mở Cài đặt"; `CalibrationScreen` hiện hướng dẫn theo `CalibrationIssue` (`tooClose` → "lùi ra xa hơn"); `ParentGate` chặn vào `ParentSettings` khi trả lời sai phép tính; `HomeScreen` có Play, chọn lớp, và chỉ có mục SayIt khi bật; `LaneJumpScreen` hiện đúng `choiceCount` làn, tô sáng `selectedLane`, `Confirmed` ở làn đúng → `TinTinState.happy` và nhãn "Đúng" có biểu tượng; `PlayerLost` → `PauseOverlay`; app `paused` → `LevelSession.phase == paused`; `ResultScreen` hiện số sao bằng `Scoring.stars`; banner quảng cáo không hiện ở `SafetyScreen`, `CalibrationScreen`, `ParentSettings`.
- [ ] **Step 2:** FAIL → cài; hiệu ứng dưới 1,5 giây, không nhấp nháy quá 3 lần/giây; nhắc nghỉ (`VoiceLine.takeABreak`) sau 20 phút chơi → PASS.
- [ ] **Step 3:** Commit `feat(ui): shell, parent area, lane jump flow`.

## Task 15: Nội dung MVP lớp 1 (2 unit)

**Files:** Create `assets/content/grade1/u01.json`, `u02.json`, `assets/images/grade1/*`, `assets/images/LICENSES.md`, `test/content/content_validity_test.dart`.

**Interfaces:** Consumes: schema Task 7, `docs/content/unit-map.md`.

- [ ] **Step 1:** Test duyệt mọi file `assets/content/**`: `id` duy nhất toàn cục; mọi `image` tồn tại trong `assets/images/` và có dòng trong `LICENSES.md`; mỗi mục có ≥ 2 `distractorIds` hợp lệ; `syllables` ≥ 1; lớp 1–2 chỉ dùng `laneJump` và `sayIt`; mục `sayIt` lớp 1–2 có `syllables <= 2`; `spokenVariants` đã chuẩn hóa (qua `WordJudge.normalize` khi Task 21 xong, trước đó kiểm chữ thường và không dấu câu) và khác `word`; mỗi unit đủ để pool level 1 (8 câu) đạt ≥ 16 cặp (mục × dạng hỏi).
- [ ] **Step 2:** FAIL → soạn 2 unit đầu lớp 1 theo `unit-map.md`, vẽ hình đồng bộ theo phương án đã chọn, thu `assets/audio/en/` cho các từ → PASS. Commit `feat(content): grade 1 units 1-2`.

## Task 16: Chơi thử trên TV (điểm kiểm tra Pha 1)

**Files:** Create `docs/superpowers/notes/playtest-phase1.md`.

- [ ] **Step 1:** Build release, chơi level 1–3 lớp 1 trên TV qua cách chiếu tốt nhất của Task 0, với ít nhất một bé 6–7 tuổi, mỗi máy một lần.
- [ ] **Step 2:** Ghi: số lần báo sai oan, số lần không nhận nhảy, bé có hiểu luật không cần người lớn giải thích không, độ dài một level, phản ứng với Tin Tin và âm thanh.
- [ ] **Step 3:** Sửa lỗi chặn; cập nhật Global Constraints nếu cần chỉnh ngưỡng; hỏi người dùng xác nhận trước khi sang Pha 2. Commit notes.

# Pha 2 – Lớp 3–5: DragSpell và SkyShoot

## Task 17: CursorTracker và HoldTracker

**Files:** Create `lib/input/cursor_tracker.dart`, `hold_tracker.dart`; Modify `lib/input/pose_session.dart` (phát `CursorMoved`); Test `test/input/cursor_tracker_test.dart`, `hold_tracker_test.dart`.

**Interfaces:**
- Produces:
  - `class CursorTracker { CursorTracker(Calibration c, {bool mirror = true, double switchMargin = 0.05}); (double, double)? update(Pose p, Duration t); Hand? get activeHand; }` — tay đang dùng là tay có cổ tay cao hơn; đổi tay chỉ khi tay kia cao hơn quá `switchMargin`; vùng với tới (ngang: `centerX ± 0.9 × thân`, dọc: từ `nose.y − 0.3 × thân` tới `midHipY`) ánh xạ ra 0..1.
  - `class HoldProgress { final String? targetId; final double progress; final bool completed; }`
  - `class HoldTracker { HoldTracker({Duration holdTime = const Duration(seconds: 1), Duration grace = const Duration(milliseconds: 200)}); HoldProgress update(String? targetId, Duration now); void reset(); }`

- [ ] **Step 1:** Test CursorTracker: tay phải cao hơn → `activeHand right`; tay trái cao hơn 0.03 → vẫn `right`; cao hơn 0.08 → `left`; cổ tay ở mép phải vùng với tới → x ≈ 1.0 (`mirror: false`); không thấy cổ tay → `null`.
- [ ] **Step 2:** Test HoldTracker: giữ `'a'` 1000 ms → `completed` một lần, 500 ms → `progress 0.5`; rời 150 ms rồi quay lại → tiến độ giữ nguyên; rời 300 ms → đặt lại; đổi sang `'b'` → đặt lại.
- [ ] **Step 3:** FAIL → cài → PASS. Commit `feat(input): cursor and hold trackers`.

## Task 18: DragSpell

**Files:** Create `lib/modes/drag_spell.dart`, `lib/ui/screens/drag_spell_screen.dart`; Test `test/modes/drag_spell_test.dart`, `test/ui/drag_spell_screen_test.dart`.

**Interfaces:**
- Consumes: `Round`, `SpellQuestion`, `OrderQuestion`, `HoldTracker`, `CursorMoved`.
- Produces: `class DragSpellRound implements Round { DragSpellRound.spell(SpellQuestion q, {required Duration timeLimit}); DragSpellRound.order(OrderQuestion q, {required Duration timeLimit}); void onTargetHeld(String targetId); List<String?> get slots; String? get carrying; }` — UI đổi vị trí con trỏ thành `targetId` (`tile:<i>`, `slot:<i>`, `check`) và báo khi `HoldTracker.completed`.

- [ ] **Step 1:** Test: giữ `tile:0` rồi `slot:1` → ô 1 có chữ; giữ `slot:1` đã có chữ → chữ được nhặt lên (`carrying`); `check` khi chưa đầy → không có kết quả; đầy và đúng → `correct`; đầy và sai → `wrong`; "apple" đặt hai chữ p đổi chỗ → `correct`; `OrderQuestion` có từ lặp ("the cat and the dog") đổi chỗ hai chữ "the" → `correct`; `PlayerLost` dừng đồng hồ; hết giờ → `timeout`.
- [ ] **Step 2:** Widget test: hiện hình gợi ý khi `hints != none`; TTS đọc từ đích lúc bắt đầu; vòng tiến độ giữ hiện quanh con trỏ.
- [ ] **Step 3:** FAIL → cài → PASS. Commit `feat(modes): drag spell`.

## Task 19: PullDetector và SkyShoot

**Files:** Create `lib/input/pull_detector.dart`, `lib/modes/sky_shoot.dart`, `lib/ui/screens/sky_shoot_screen.dart`; Modify `pose_session.dart` (phát `Pulled`); Test `test/input/pull_detector_test.dart`, `test/modes/sky_shoot_test.dart`.

**Interfaces:**
- Produces:
  - `class PullDetector { PullDetector(Calibration c, {double minTravel = 0.4}); Hand? update(Pose p, Duration t); }` — trả tay vừa hoàn thành một nhịp (xuống ≥ `minTravel × thân`, lên ≥ nửa quãng).
  - `class SkyField { SkyField({required Random rng, required int answerCount, required double sweepSpeed}); double arrowX(Duration t); double answerX(int i, Duration t); }` — mũi tên quét 0.1..0.9 với hướng/tốc độ ngẫu nhiên ±20% quanh `sweepSpeed`; đáp án trôi chậm, không chồng nhau.
  - `enum SkyPhase { aiming, reeling, resolved }`
  - `class SkyShootRound implements Round { SkyShootRound(ChoiceQuestion q, {required Duration timeLimit, required SkyField field, required Duration castLatency, double hitRadius = 0.08, int shots = 3, int pullsNeeded = 4}); SkyPhase get phase; int get shotsLeft; int? get hitIndex; int get pulls; }` — `Confirmed(at)` bắn tại `field.arrowX(at − castLatency)`; trúng → `reeling`, đồng hồ dừng; `Pulled` chỉ tính khi khác tay lần trước.

- [ ] **Step 1:** Test PullDetector: thân 0.3, tay trái xuống 0.15 rồi lên → `left`; chuyển động 0.05 → `null`.
- [ ] **Step 2:** Test SkyShoot với `SkyField` giả: `shotsLeft` 3; trượt hai lần → 1, vẫn `aiming`; trượt lần ba → `wrong`; bé nhảy lúc mũi tên ở trên đáp án đúng nhưng sự kiện đến muộn 300 ms (mũi tên đã đi qua) với `castLatency 300ms` → vẫn trúng (Review Focus); trúng đáp án đúng, `Pulled` trái-phải-trái-phải → `correct`; trái-trái → `pulls == 1`; trúng đáp án sai và kéo đủ → `wrong`; `Confirmed` khi `reeling` bị bỏ qua; khi `reeling`, `tick(30s)` không gây `timeout`; với `Random(7)` qua 50 câu, hướng quét ban đầu có cả trái lẫn phải.
- [ ] **Step 3:** Widget test: hiện số lượt bắn còn lại và số lần kéo; animation chúc mừng khi `correct`.
- [ ] **Step 4:** FAIL → cài → PASS. Commit `feat(modes): pull detector and sky shoot`.

## Task 20: Nội dung lớp 3 (2 unit) và chơi thử Pha 2

**Files:** Create `assets/content/grade3/u01.json`, `u02.json`, hình tương ứng; `docs/superpowers/notes/playtest-phase2.md`.

- [ ] **Step 1:** Mở rộng `content_validity_test.dart`: lớp 3–5 mỗi unit có ≥ 1 mục `dragSpell` và ≥ 1 mục `skyShoot`; mục `dragSpell` có `word` ≥ 3 chữ cái; câu trong `sentencePatterns` dùng cho `orderSentence` có 3–6 từ.
- [ ] **Step 2:** FAIL → soạn → PASS.
- [ ] **Step 3:** Chơi thử với một bé 9–10 tuổi trên TV: một level trộn ba mode; ghi lỗi; sửa lỗi chặn. Commit `feat(content): grade 3 units 1-2` và notes.

# Pha 3 – SayIt (chỉ khi Task 0 đạt phần giọng nói)

## Task 21: WordJudge và nguồn nhận dạng trên máy

**Files:** Create `lib/speech/word_judge.dart`, `speech_source.dart`, `speech_session.dart`, `on_device_speech_source.dart` (+ native/thư viện theo Task 0); Modify `AndroidManifest.xml` (quyền `RECORD_AUDIO`); Test `test/speech/word_judge_test.dart`, `speech_session_test.dart`.

**Interfaces:**
- Produces:
  - `class RecognitionResult { final List<String> transcripts; final List<double>? confidences; final int sessionId; }`
  - `class WordJudge { static String normalize(String s); static bool matches(RecognitionResult r, ContentItem item, {double minConfidence = 0.3}); }`
  - `enum SpeechAvailability { available, noPermission, noOnDeviceRecognizer }`
  - `abstract class SpeechSource { Future<SpeechAvailability> check(); Stream<RecognitionResult> listenOnce({required int sessionId}); Future<void> stop(); }` — chỉ triển khai bộ nhận dạng trên máy; luồng kết thúc khi bộ nhận dạng dừng.
  - `class SpeechSession { SpeechSession(SpeechSource s, AudioService audio); Stream<RecognitionResult> listenWhile({required int sessionId, required bool Function() keepListening}); Future<void> cancel(); }` — gọi `audio.muteForListening()` trước, tự gọi lại `listenOnce` khi luồng kết thúc mà `keepListening()` còn đúng, luôn `restoreAfterListening()` khi xong hoặc lỗi.

- [ ] **Step 1:** Test WordJudge: `normalize('  The Hand!! ') == 'hand'`; `normalize('T-shirt') == 't shirt'`; `normalize('8') == 'eight'`; khớp ở kết quả thứ ba; khớp `spokenVariants`; `['hat']` → sai; kết quả trùng với `confidences [0.1]` → sai; `confidences [0.9, 0.0, -1]` và từ đích ở vị trí 2 → đúng (≤ 0 coi như không có điểm); `transcripts` rỗng → sai; `'a hand please'` → sai.
- [ ] **Step 2:** Test SpeechSession với nguồn giả: luồng 1 kết thúc khi `keepListening` còn đúng → gọi `listenOnce` lần 2; `keepListening` sai → dừng; nguồn ném lỗi → `restoreAfterListening` vẫn được gọi, không ném ra ngoài; `mute` trước khi nghe.
- [ ] **Step 3:** Test `OnDeviceSpeechSource.check()` với channel giả: máy không có bộ trên máy → `noOnDeviceRecognizer` (Review Focus: không bao giờ rơi về bộ gửi lên mạng); từ chối micro → `noPermission`.
- [ ] **Step 4:** FAIL → cài → PASS. Thử trên hai máy ở chế độ máy bay. Commit `feat(speech): judge, on-device source, session`.

## Task 22: SayIt game và màn hình

**Files:** Create `lib/modes/say_it.dart`, `lib/ui/screens/say_it_screen.dart`; Test `test/modes/say_it_test.dart`, `test/ui/say_it_screen_test.dart`.

**Interfaces:**
- Consumes: `ContentItem`, `RecognitionResult`, `WordJudge`, `SpeechSession`, `AudioService`, `QuestionGenerator.sayItWords`, `Scoring.sayItStars`.
- Produces:
  - `enum WordMotion { fallDown, rightToLeft }`; `enum WordPhase { waitingForModel, running, judged, exploding, gone }`
  - `class SayItWord { final ContentItem item; final WordMotion motion; final int sessionId; WordPhase phase; RoundResult? result; double progress; }`
  - `class SayItRound { SayItRound(List<ContentItem> items, {required Duration travelTime, required Random rng, required bool modelFirst, required int firstSessionId}); void onModelFinished(); void onRecognized(RecognitionResult r); void tick(Duration dt); SayItWord get current; bool get finished; int get correctCount; }` — đúng 3 mục; `modelFirst` (lớp 1–2) bắt đầu ở `waitingForModel`; kết quả có `sessionId` khác từ hiện tại bị bỏ; kết quả trong 1 giây sau khi từ chạy hết vẫn tính.
  - `class SayItLevel { SayItLevel({required List<SayItRound> rounds}); int get correctOfNine; int get stars; }`
  - Hằng: `kJudgedHold = 700ms`, `kExplosionTime = 800ms`, `kLateGrace = 1s`.

- [ ] **Step 1:** Test SayItRound: không đúng 3 mục → `ArgumentError`; `modelFirst` → `waitingForModel`, `tick` không chạy `progress` tới khi `onModelFinished`; `tick(travelTime/2)` → `progress 0.5`; khớp → `judged/correct`, sau 700 ms → `exploding`, sau 800 ms → `gone`, `current` sang từ 2; không khớp → `wrong`; chạy hết, không kết quả, sau `kLateGrace` → `wrong` rồi nổ; kết quả khớp đến trong `kLateGrace` → `correct`; kết quả mang `sessionId` của từ trước → bị bỏ (Review Focus); `onRecognized` khi `judged`/`exploding` bị bỏ; xong 3 từ → `finished`; `Random(1)` qua 20 ván có cả hai `WordMotion`.
- [ ] **Step 2:** Test SayItLevel: 3 ván với 8/9 đúng → `stars 3`; 6/9 → 1.
- [ ] **Step 3:** Widget test: từ chạy đúng hướng theo `motion`; nhãn "Đúng"/"Sai" có biểu tượng khi `judged`; hiệu ứng nổ khi `exploding`; không còn widget từ khi `gone`; theo dõi pose tắt trong màn này; mục SayIt ẩn trên `HomeScreen` khi `check()` không `available`.
- [ ] **Step 4:** FAIL → cài → PASS. Commit `feat(modes): say-it`.

# Pha 4 – Nội dung đầy đủ, quảng cáo, phát hành

## Task 23: Nội dung lớp 1–5 đầy đủ

**Files:** `assets/content/grade{1..5}/*.json`, `assets/images/**`, `assets/audio/en/**`.

- [ ] **Step 1:** Mỗi lớp một nhánh và một commit, theo thứ tự lớp 3, 4, 5, 1, 2; điền `spokenVariants` từ Task 0 và chơi thử.
- [ ] **Step 2:** `content_validity_test.dart` PASS sau mỗi lớp.
- [ ] **Step 3:** Giáo viên hoặc người dùng rà từ vựng với sách thật; ghi người rà và ngày vào `docs/content/unit-map.md`.

## Task 24: Quảng cáo và tuân thủ Families

**Files:** Create `lib/ads/ads_config.dart`, `lib/ads/corner_banner.dart`, `docs/privacy-policy.md`, `docs/data-safety.md`; Test `test/ads/ads_config_test.dart`.

**Interfaces:**
- Produces: `class AdsConfig { static const childDirected = true; static const maxContentRating = 'G'; static const nonPersonalized = true; static const useAdvertisingId = false; }`; `class CornerBanner extends StatelessWidget` (cỡ banner nhỏ, góc cố định).

- [ ] **Step 1:** Test: các hằng như trên; `CornerBanner` không vượt 320×50 dp; không có `CornerBanner` trong cây widget của `SafetyScreen`, `CalibrationScreen`, `ParentSettings`, `PauseOverlay` (đã có ở Task 14, mở rộng cho Pause).
- [ ] **Step 2:** Chọn SDK trong danh sách Families của Google; khai báo cấu hình hướng tới trẻ em trong SDK. FAIL → cài → PASS.
- [ ] **Step 3:** Viết chính sách quyền riêng tư và khai báo Data safety (camera/micro xử lý trên máy, không thu thập dữ liệu cá nhân); liên kết từ `ParentSettings` sau cổng phụ huynh. Commit `feat(ads): families-compliant corner banner and privacy docs`.

## Task 25: Kiểm thử thiết bị và chuẩn bị phát hành

**Files:** `docs/superpowers/notes/device-qa.md`.

- [ ] **Step 1:** Mỗi máy: 20 phút chơi liền qua TV ở cả bốn chế độ; ghi fps, nhiệt, báo sai oan, crash.
- [ ] **Step 2:** Kiểm tra chế độ máy bay: mọi chế độ trừ quảng cáo vẫn chạy; SayIt vẫn chạy (bộ trên máy).
- [ ] **Step 3:** Rà lại yêu cầu pháp lý về dữ liệu trẻ em ở nước phát hành; trang Store không dùng tên bộ sách như nhãn hiệu.
- [ ] **Step 4:** Build app bundle, thử nội bộ trên Play Console (internal testing). Commit notes.

## Self-review

- **Độ phủ spec v2:** điều khiển và hiệu chỉnh (Task 2–6, 17, 19), không chắc thì không chấm (5, 10, 22), độ trễ cast (0, 19), chế độ không nhảy (3, 5, 13), LaneJump/DragSpell/SkyShoot/SayIt (10, 18, 19, 21–22), unit đang học và level (7, 13), random hóa (9), LevelSession và ôn câu sai (11), thời gian/điểm/sao (8), âm thanh tiếng Việt, phụ đề (12), an toàn, cổng phụ huynh, nhắc nghỉ (13–14), hình ảnh và giấy phép (15, 23), quyền riêng tư và Families (1, 21, 24), thiết bị tầm trung và fps (0, 25).
- **Nhất quán kiểu:** `Confirmed(lane)` thay cho "Jumped" ở mọi task; `Round`, `RoundResult`, `PlannedQuestion`, `HistoryStore` (`recordAsked`, `markWrong`, `clearWrong`), `ConfirmGesture`, `PermissionOutcome` định nghĩa một lần.
- **Phụ thuộc:** Task 0 → ngưỡng cho Task 3–5, 19, quyết định nguồn pose cho Task 6 và nguồn giọng nói cho Task 21; Task 7 Step 5 (`unit-map.md`) → Task 15, 20, 23; Task 16 là điểm dừng hỏi người dùng trước Pha 2; Pha 3 chỉ làm khi Task 0 đạt phần giọng nói.
