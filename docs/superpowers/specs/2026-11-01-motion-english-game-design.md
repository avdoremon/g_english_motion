# Game học tiếng Anh tiểu học bằng chuyển động (Motion English) – Thiết kế

Ngày: 2026-11-01. Phiên bản 2 (đã sửa theo review độc lập). Trạng thái: chờ người dùng duyệt.

## 1. Mục tiêu và phạm vi

Bản tiếng Anh của game học toán motion: bé đứng trước camera điện thoại, game chiếu lên TV (mirroring/HDMI), bé điều khiển bằng cơ thể và không cần nhìn màn hình điện thoại.

- Đối tượng: học sinh tiểu học lớp 1–5, chơi ở nhà (1 bé), miễn phí, quảng cáo chỉ là banner nhỏ ở góc, không bao giờ chen ngang. Phát hành trên Google Play theo chương trình Families (mục 10).
- Nội dung bám Chương trình GDPT 2018, bộ sách **Global Success** (Kết nối tri thức). Cấu trúc dữ liệu cho phép thêm bộ sách khác sau này, nhưng MVP chỉ làm Global Success.
- Nền tảng: Android trước. Máy kiểm thử chính Galaxy S24 Ultra (Android 17) **và một máy tầm trung đời 2021–2022**; hỗ trợ điện thoại khoảng 4 năm gần đây. iOS làm sau. Màn hình khóa ngang, giữ sáng màn hình khi đang chơi.
- Stack: Flutter (bản stable ghim cụ thể khi khởi tạo) + Flame + MediaPipe Pose, cùng stack với game toán.
- Kế thừa từ game toán: mascot Tin Tin, 100 điểm mỗi câu đúng, sai thì báo sai và giải thích đáp án đúng, không đăng nhập ở MVP, tiến độ lưu cục bộ.
- **Quy tắc quyền riêng tư (bắt buộc):** khung hình camera và âm thanh micro chỉ xử lý trên máy, không lưu, không gửi đi. Ngoài SDK quảng cáo, không module nào được gọi mạng.
- Ngoài phạm vi MVP: iOS, đăng nhập và bảng xếp hạng, chế độ trường học, ứng dụng riêng trên TV, chấm phát âm chi tiết theo âm vị (SayIt chỉ kiểm tra "nói đúng từ"), nhận dạng cử chỉ bàn tay (Hand Landmarker).

## 2. Điều khiển bằng cơ thể (hướng A: chỉ dùng Pose)

Một model duy nhất: MediaPipe Pose, theo dõi tối đa 2 người mỗi khung hình để chọn đúng bé. Lớp Input chỉ phát ra các sự kiện đã chuẩn hóa, mỗi sự kiện mang **thời điểm của khung pose** sinh ra nó; các chế độ chơi không đụng tới dữ liệu camera thô.

| Sự kiện | Nguồn | Ghi chú |
|---|---|---|
| `LaneChanged(lane)` | Trung điểm hông theo trục ngang | Bề rộng làn = 0,6 × chiều cao thân (tự co giãn theo khoảng cách đứng); vùng trễ 10% bề rộng làn để không nhấp nháy ở ranh giới; lật trục x cho camera trước |
| `Confirmed(lane)` | Nhảy (mặc định) hoặc giơ hai tay (chế độ không nhảy) | `lane` là làn ngay trước lúc bật nhảy, không phải làn lúc đang bay |
| `CursorMoved(x,y)` | Cổ tay của tay đang giơ cao hơn | Đổi tay chỉ khi tay kia cao hơn rõ rệt (vùng trễ); vùng với tới quanh vai được ánh xạ ra toàn màn hình |
| `Pulled(hand)` | Cổ tay đi xuống rồi lên | Mỗi nhịp kéo một sự kiện; luật "hai tay luân phiên" do SkyShoot kiểm |
| `PlayerLost` / `PlayerFound` | Mất pose của bé quá 500 ms / có lại | Mọi đồng hồ tạm dừng khi mất người |

**Nhảy:** vượt ngưỡng khi độ nâng trung bình của trung điểm hông và trung điểm vai so với mốc chuẩn ≥ 12% chiều cao thân; sự kiện phát ngay lúc vượt ngưỡng (độ trễ thấp); chỉ nạp lại khi bé hạ xuống dưới nửa ngưỡng và đã qua 600 ms. Mốc chuẩn tự cập nhật chậm khi bé đứng yên (bé tiến/lùi không làm trôi ngưỡng). Landmark được lọc nhiễu trước khi xử lý. Bỏ qua cú nhảy trong 500 ms đầu mỗi câu và ở khung đầu tiên sau `PlayerFound`.

**Chế độ không nhảy** (bật trong khu vực phụ huynh): giơ hai tay cao quá đầu 0,5 giây thay cho nhảy. Dành cho nhà chung cư, trẻ khó vận động, hoặc phụ huynh chơi thử.

**Hiệu chỉnh:** đầu mỗi phiên, bé đứng yên gần giữa khung hình khoảng 2 giây; hệ thống lấy trung bình nhiều khung, kiểm tra thấy đủ đầu, vai, hông, đầu gối (còn khoảng trống phía trên để nhảy). Người được chọn là người đứng yên gần tâm khung nhất trong 2 giây đó; sau đó bám theo người có vị trí và chiều cao thân gần nhất, bỏ qua người khác (ví dụ phụ huynh đi ngang). Thiếu thân người thì Tin Tin hướng dẫn "lùi ra xa hơn" kèm hình mẫu.

**Độ trễ khi cast:** độ trễ từ lúc bé bật nhảy đến lúc hình đổi trên TV (gồm suy luận, vẽ, mirroring) được đo ở spike và lưu thành tham số; SkyShoot chấm trúng/trượt theo vị trí mũi tên tại thời điểm khung pose, không phải lúc sự kiện tới nơi.

**Nguyên tắc "không chắc thì không chấm":** đầu vào không đáng tin (độ tin cậy pose thấp đúng lúc chốt, làn đang dao động, kết quả giọng nói về trễ sang từ khác) thì bỏ qua và chờ, không bao giờ báo "Sai" vì lỗi nhận dạng.

**Spike đo đạc** là việc đầu tiên của kế hoạch: đo độ chính xác, độ trễ đến TV, fps và nhiệt sau 20 phút trên cả hai máy, với trẻ 6–7 tuổi và 9–10 tuổi; quyết định plugin pose; có phương án "giơ hai tay" nếu nhảy không đạt.

## 3. Các chế độ chơi

Mọi chế độ dùng chung một khung câu hỏi: câu hỏi được đọc (TTS) trước, **đồng hồ chỉ chạy sau khi đọc xong**; sai thì Tin Tin báo bằng lời tiếng Việt thu sẵn, nói đáp án đúng và đọc lại từ tiếng Anh.

### 3.1 LaneJump (lớp 1–2)
TTS đọc câu hỏi (hoặc hiện hình). Màn hình chia 3–4 làn, mỗi làn một đáp án (hình hoặc từ). Bé bước sang trái/phải để đứng đúng làn (làn ban đầu là làn bé đang đứng), rồi nhảy để chốt.

### 3.2 DragSpell (lớp 3–5): kéo thả ghép từ
Giữ tay 1 giây trên chữ cái (hoặc từ) để nhặt, di chuyển, giữ 1 giây trên ô trống để thả. Giữ trên ô đã có chữ thì nhặt chữ đó lên lại. Rời mục tiêu dưới 200 ms không mất tiến độ giữ. Nút "Kiểm tra" là một ô giữ tay 1 giây. Hai biến thể: ghép chữ cái thành từ; sắp xếp các từ thành câu. Đầu câu, TTS đọc từ (hoặc câu) cần ghép; level 1–3 có thêm hình gợi ý. Chữ hoặc từ lặp (ví dụ hai chữ p trong "apple") đổi chỗ cho nhau vẫn đúng.

### 3.3 SkyShoot (lớp 3–5): nhảy bắn mũi tên
Trên trời có 3–4 đáp án trôi chậm. Một mũi tên quét qua lại liên tục (hướng và tốc độ ngẫu nhiên trong giới hạn của level). Bé nhảy (hoặc giơ hai tay) thì mũi tên bắn đi. Trúng đáp án nào thì đáp án đó bị câu xuống và **đồng hồ dừng**; bé làm động tác kéo dây hai tay luân phiên 4 lần để kéo đáp án về. Sau đó game kiểm tra: đúng thì có animation chúc mừng; sai thì Tin Tin giải thích và câu kết thúc (tính sai). Bắn trượt thì mũi tên quay về và mất một lượt; tối đa 3 lượt bắn mỗi câu, hết lượt coi như sai.

### 3.4 SayIt (mini-game đọc to)

Mini-game riêng trên menu. Mỗi **ván có 3 từ chạy lần lượt**; mỗi từ chạy theo một trong hai kiểu (ngẫu nhiên): **rơi từ trên xuống** hoặc **đi từ phải qua trái**. Bé đọc to từ đang chạy; hệ thống nhận dạng và chấm. Khi có kết quả, từ hiện "Đúng" hoặc "Sai" (kèm biểu tượng và Tin Tin vui/buồn, không chỉ khác màu), rồi **nổ và biến mất**; từ kế tiếp xuất hiện. Từ chạy hết màn hình mà chưa có kết quả thì tính sai, rồi cũng nổ và biến mất. Một level SayIt gồm 3 ván (9 từ).

- **Nhận dạng chỉ trên máy:** âm thanh không rời thiết bị. Spike chọn giữa bộ nhận dạng trên máy của Android (API 31+, khi máy có) và một bộ nhận dạng offline nhúng trong app giới hạn từ vựng (từ đích + từ nhiễu). Máy không có bộ nhận dạng trên máy dùng được thì SayIt bị ẩn; các chế độ khác vẫn chơi.
- **Nghe:** micro mở khi từ bắt đầu chạy và tự mở lại nếu bộ nhận dạng dừng vì im lặng, cho tới khi từ chạy hết. Kết quả gắn với từ đang chạy; kết quả về muộn trong 1 giây sau khi từ chạy hết vẫn tính cho từ đó, muộn hơn thì bỏ. Trong lúc nghe, tắt nhạc nền và hiệu ứng âm thanh để micro không thu tiếng TV. SayIt không cần camera: tắt theo dõi pose, bé có thể đứng gần điện thoại 0,5–1 m.
- **Chấm:** đúng khi bất kỳ kết quả thay thế nào, sau chuẩn hóa, trùng từ đích hoặc một `spokenVariants`. Chuẩn hóa: chữ thường, bỏ dấu câu, gạch nối thành khoảng trắng, số viết bằng chữ số đổi thành chữ (0–100), bỏ mạo từ a/an/the ở đầu. Điểm tin cậy chỉ xét khi máy cung cấp giá trị > 0, và phải ≥ 0,3. Không chấm gần đúng theo khoảng cách chữ cái.
- **Lớp 1–2:** TTS đọc mẫu từ trước, từ chỉ bắt đầu chạy (và micro chỉ mở) sau khi đọc xong; chỉ dùng từ ≤ 2 âm tiết. **Lớp 3–5:** không đọc mẫu, từ dài hơn ở level cao.
- **Sao của level SayIt (9 từ):** 1 sao từ 5 từ đúng, 2 sao từ 7, 3 sao từ 8.

## 4. Nội dung

- Nguồn: danh sách từ vựng và mẫu câu tự soạn theo chủ đề từng unit của Global Success (từ vựng là dữ kiện; không sao chép văn bản sách). Một giáo viên hoặc người dùng rà soát một lần cho khớp sách.
- Cấu trúc sách đã xác nhận qua nguồn: lớp 1 và 2 mỗi lớp 16 unit; lớp 3 có Starter + Unit 1–20 + 4 Review; lớp 4 có Starter + 20 unit + 4 Review; lớp 5 có Starter + Unit 1–20. Tên unit đầy đủ được đối chiếu với mục lục chính thức ở kế hoạch triển khai.
- **Unit đang học:** phụ huynh chọn unit con đang học cho từng lớp (mặc định Unit 1) trong khu vực phụ huynh. Level lấy nội dung tính từ mốc đó (mục 5).
- Định dạng dữ liệu: JSON theo `grade/unit`; mỗi mục gồm `id`, `word`, `ttsText`, `image`, `syllables`, `sentencePatterns[]`, `distractorIds[]` (tham chiếu mục khác để dùng được cả hình lẫn chữ), `spokenVariants[]`, `modes[]`. Thêm unit chỉ cần thêm dữ liệu.
- **Hình ảnh:** vẽ đồng bộ theo phương án đồ họa được chọn; mọi ảnh có nguồn và giấy phép ghi trong `assets/images/LICENSES.md`. MVP chỉ làm 2 unit lớp 1 trước khi mở rộng.
- **Âm thanh:** từ tiếng Anh đọc bằng TTS `en-US`; các câu hướng dẫn, khen, động viên và giải thích bằng **tiếng Việt thu sẵn** (bộ câu cố định, có chỗ ghép từ tiếng Anh). Lớp 1–2 có file thu sẵn cho từ cốt lõi để không phụ thuộc giọng TTS của máy. Mọi lời đọc có phụ đề.

### Random hóa câu hỏi

- **Pool:** tính theo cặp (mục × dạng hỏi). Mục tiêu pool ≥ 2 lần số câu của level; unit nhỏ không đủ thì cho lặp lại sau khi đã dùng hết pool, không bao giờ thiếu câu.
- **Xáo trộn:** thứ tự câu, vị trí đáp án đúng (không cùng vị trí quá 2 câu liên tiếp), đáp án nhiễu (cùng unit trước, thiếu thì lấy unit đã học), thứ tự chữ cái (không trùng thứ tự đúng), hướng và tốc độ mũi tên, kiểu chạy của từ trong SayIt.
- **Tránh lặp giữa các lần chơi:** ưu tiên mục chưa hỏi gần đây (lưu 200 mục gần nhất).
- **Ôn câu sai:** trong lượt, câu sai được hỏi lại một lần ở cuối lượt dưới dạng ôn tập (không tính điểm, không tính sao). Giữa các lượt, mục sai gần đây được ưu tiên cao nhất nhưng tối đa 30% số câu và không ở câu đầu; mục được gỡ khỏi danh sách sai khi bé trả lời đúng.
- **Đổi cách hỏi:** cùng một mục có thể hỏi bằng nghe-chọn-hình, nhìn-hình-chọn-từ, nghe-chọn-từ, điền từ, ghép chữ, tùy lớp và mode. Lớp 3–5 trộn ba mode trong cùng một level.
- **Kiểm thử:** bộ sinh nhận seed để test lặp lại được.

## 5. Level, thời gian và độ khó

Mỗi lớp có 5 level; cấu hình nằm trong file `assets/config/levels.json`.

| Level | Số câu | Thời gian cơ bản mỗi câu | Số đáp án | Gợi ý hình | Unit dùng |
|---|---|---|---|---|---|
| 1 Khởi động | 8 | 20 giây | 3 | Có | Unit đang học |
| 2 | 10 | 18 giây | 3 | Có | Unit đang học + 1 unit trước |
| 3 | 10 | 15 giây | 4 | Ít | Unit đang học + 2 unit trước |
| 4 | 12 | 12 giây | 4 | Không | Ôn mọi unit đã học |
| 5 Thử thách | 12 | 10 giây | 4 | Không | Trộn mọi unit đã học, từ/câu dài |

- Thời gian thực mỗi câu: chọn đáp án (LaneJump) = cơ bản; SkyShoot = cơ bản × 1,5 và dừng khi đã trúng; DragSpell = cơ bản + 3 giây × số ô; SayIt = thời gian từ chạy hết màn hình = cơ bản.
- Sao (tính bằng số nguyên): 1 sao từ 50%, 2 sao từ 75%, 3 sao từ 90% số câu đúng (riêng SayIt theo mục 3.4). 100 điểm mỗi câu đúng; câu ôn tập không tính.
- Level N+1 mở khóa khi level N được ít nhất 1 sao.

## 6. Kiến trúc

1. `input/` – kiểu pose, bộ lọc nhiễu, hiệu chỉnh, phát hiện nhảy/giơ tay, theo dõi làn, con trỏ, giữ, kéo; `PoseSession` chọn và bám người chơi, phát sự kiện. Nguồn khung hình thật (MediaPipe) nằm sau giao diện, thay được bằng nguồn giả và chuỗi landmark ghi thật từ spike.
2. `modes/` – mỗi chế độ là một `Round` (nhận sự kiện, đếm giờ, trả kết quả).
3. `session/` – `LevelSession` điều phối một lượt chơi: hàng đợi câu hỏi, chờ đọc xong mới đếm giờ, tạm dừng, ôn câu sai, tính điểm/sao, ghi lịch sử.
4. `content/` – nạp JSON, unit theo mốc đang học, sinh câu hỏi có random hóa.
5. `levels/` – cấu hình level, thời gian, điểm, sao.
6. `audio/` – TTS, lời Việt thu sẵn, phụ đề, nhạc/hiệu ứng, tắt tiếng khi nghe; `speech/` – nhận dạng trên máy và chấm từ.
7. `progress/` – tiến độ, unit đang học, lịch sử, cài đặt phụ huynh (lưu cục bộ).
8. `ui/` – shell (quyền, cảnh báo an toàn, hiệu chỉnh, tạm dừng, giữ màn hình sáng), khu vực phụ huynh, các màn chơi, mascot, theme.
9. `ads/` – banner góc theo chuẩn Families; module duy nhất được dùng mạng.

**Xử lý lỗi:** mất người chơi hoặc app xuống nền thì tạm dừng mọi đồng hồ; quyền camera bị từ chối thì màn giải thích cho phụ huynh, từ chối vĩnh viễn thì nút mở Cài đặt; TTS không có thì phát file thu sẵn và phụ đề; không có nhận dạng giọng nói trên máy hoặc không có quyền micro thì ẩn SayIt.

## 7. Animation dễ thương

Tin Tin có các trạng thái: chờ, vui, buồn, cổ vũ, nhảy múa. Chữ cái nhún nhảy khi nhặt, ô trống phát sáng nhẹ khi tay tới gần, pháo hoa sao khi trúng, từ nổ tung trong SayIt, mây và sao trôi nhẹ ở nền, Tin Tin trao sao cuối level. Mọi hiệu ứng ngắn (dưới 1,5 giây); không nhấp nháy quá 3 lần mỗi giây.

## 8. Đồ họa: ba phương án (Claude Design)

Bản dựng: https://claude.ai/artifact/TsnrqbHnzA9aNQkK8ktCo2 (mỗi phương án 3 màn: màn chính, SkyShoot, DragSpell; các màn còn lại dựng theo phương án được chọn). Tin Tin trong bản dựng là hình tạm; thay bằng mascot thật khi có tệp gốc, việc lập trình giao diện không chờ việc này.

- **A – Khu vườn mây:** pastel mềm, mây bông, cỏ tròn trịa; dịu mắt.
- **B – Phi hành đoàn vũ trụ:** nền vũ trụ đậm, planet và tên lửa; tương phản mạnh khi chiếu TV.
- **C – Thị trấn kẹo giấy:** giấy cắt dán, màu kẹo, máy bay giấy; khác hẳn game toán.

Yêu cầu chung: chữ lớn, tương phản cao để đọc từ 2–3 m; làn và ô lớn; không đặt chi tiết quan trọng sát viền; banner quảng cáo nhỏ ở một góc, không che gameplay.

## 9. An toàn và khả năng truy cập

- Màn cảnh báo đầu phiên: dọn khoảng trống trước TV, cố định điện thoại; phụ huynh xác nhận một lần.
- Nhắc nghỉ sau mỗi 20 phút chơi (gợi ý bài vận động nhẹ của game toán làm sau).
- Phụ đề cho mọi lời đọc; đúng/sai phân biệt bằng biểu tượng và lời, không chỉ bằng màu.
- Khu vực phụ huynh có cổng xác nhận người lớn; chứa: chọn unit đang học, chế độ không nhảy, bật/tắt SayIt, chính sách quyền riêng tư.

## 10. Phát hành cho trẻ em (Google Play Families)

- Chính sách quyền riêng tư và khai báo Data safety nêu rõ: camera và micro xử lý trên máy, không thu thập dữ liệu cá nhân.
- SDK quảng cáo nằm trong danh sách được chứng nhận cho Families; bật chế độ hướng tới trẻ em, quảng cáo không cá nhân hóa, mức nội dung G, không dùng mã quảng cáo.
- Liên kết ra ngoài và cài đặt nằm sau cổng phụ huynh.
- Trang Store ghi "bám theo chương trình tiếng Anh tiểu học", không dùng tên bộ sách như nhãn hiệu.
- Trước khi phát hành, rà lại yêu cầu pháp lý về dữ liệu trẻ em tại các nước phát hành (ít nhất Việt Nam), vì các quy định có thể thay đổi.

## 11. Giả định đã chọn

- Tên tạm: "Tin Tin English".
- Repo: `avdoremon/g_english_motion`; spec và kế hoạch trong `docs/superpowers/`.
- Các ngưỡng (12% nhảy, 0,6 × thân cho làn, 4 lần kéo, 0,3 tin cậy, độ trễ cast) là giá trị khởi đầu, chốt lại sau spike.
- SayIt: ba từ chạy lần lượt (không cùng lúc); chỉ nhận dạng trên máy.
