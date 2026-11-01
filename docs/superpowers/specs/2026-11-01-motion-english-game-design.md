# Game học tiếng Anh tiểu học bằng chuyển động (Motion English) – Thiết kế

Ngày: 2026-11-01. Trạng thái: chờ người dùng duyệt spec.

## 1. Mục tiêu và phạm vi

Bản tiếng Anh của game học toán motion: bé đứng trước camera điện thoại, game chiếu lên TV (mirroring/HDMI), bé điều khiển bằng cơ thể và không cần nhìn màn hình điện thoại.

- Đối tượng: học sinh tiểu học lớp 1–5, chơi ở nhà (1 bé), miễn phí, quảng cáo chỉ là banner nhỏ ở góc, không bao giờ chen ngang.
- Nội dung bám Chương trình GDPT 2018, bộ sách **Global Success** (Kết nối tri thức). Cấu trúc dữ liệu cho phép thêm bộ sách khác sau này, nhưng MVP chỉ làm Global Success.
- Nền tảng: Android trước (máy kiểm thử: Galaxy S24 Ultra, Android 17), hỗ trợ điện thoại khoảng 4 năm gần đây. iOS làm sau.
- Stack: Flutter + Flame + MediaPipe Pose, cùng stack với game toán.
- Kế thừa từ game toán: mascot Tin Tin, 100 điểm mỗi câu đúng, sai thì báo sai và giải thích đáp án đúng, không đăng nhập ở MVP, tiến độ lưu cục bộ.
- Ngoài phạm vi MVP: iOS, đăng nhập và bảng xếp hạng, chế độ trường học, ứng dụng riêng trên TV, nhận dạng giọng nói/chấm phát âm, nhận dạng cử chỉ bàn tay (Hand Landmarker).

## 2. Điều khiển bằng cơ thể (hướng A: chỉ dùng Pose)

Một model duy nhất: MediaPipe Pose. Lớp Input chỉ phát ra các sự kiện đã chuẩn hóa; các chế độ chơi không bao giờ đụng tới dữ liệu camera thô.

| Sự kiện | Nguồn | Ghi chú |
|---|---|---|
| `lane(x)` | Trục ngang của hông, chia thành 3–4 làn | Làn hiện tại được tô sáng trên TV |
| `jump` | Hông và vai dịch lên quá ngưỡng 12% chiều cao thân so với chuẩn lúc hiệu chỉnh, rồi hạ xuống | Debounce 600 ms để một cú nhảy không tính hai lần |
| `cursor(x,y)` | Cổ tay (tay có độ tin cậy cao hơn) | Dùng cho DragSpell |
| `hold(target)` | Con trỏ ở trong một mục tiêu liên tục đủ thời gian | 1 giây để nhặt/thả chữ và bấm "Kiểm tra" trong DragSpell |
| `pull` | Cổ tay đi xuống một đoạn tối thiểu rồi trở lên, tính theo từng tay | Dùng để kéo đáp án về trong SkyShoot |

**Hiệu chỉnh (Calibration):** đầu mỗi phiên chơi, bé đứng thẳng khoảng 2 giây để đo chiều cao thân và vị trí giữa. Nếu không thấy đủ thân người, game hiện hướng dẫn "lùi ra xa hơn" bằng Tin Tin, kèm hình mẫu.

**Rủi ro và cách giảm:** độ trễ nhảy, phòng thiếu sáng, bé đứng lệch. Giảm bằng mũi tên chậm, vùng trúng rộng, hiệu chỉnh đầu phiên, và chỉ báo "đã thấy bạn" luôn hiện ở góc màn hình. Cần một **spike đo đạc** (prototype bỏ đi) trên S24 Ultra để xác nhận độ trễ và độ chính xác phát hiện nhảy trước khi cam kết ngưỡng nêu trên; đây là nhiệm vụ đầu tiên của kế hoạch triển khai.

## 3. Ba chế độ chơi

### 3.1 LaneJump (lớp 1–2)
TTS đọc câu hỏi (hoặc hiện hình). Màn hình chia 3–4 làn, mỗi làn một đáp án (hình hoặc từ). Bé bước sang trái/phải để đứng đúng làn, rồi nhảy một cái để chốt. Đúng thì Tin Tin ăn mừng; sai thì Tin Tin nói đáp án đúng và TTS đọc lại.

### 3.2 DragSpell (lớp 3–5): kéo thả ghép từ
Giữ tay 1 giây trên chữ cái (hoặc từ) để nhặt, di chuyển, giữ 1 giây trên ô trống để thả. Hai biến thể: ghép chữ cái thành từ có hình gợi ý; sắp xếp các từ thành câu. Có thể nhặt lại chữ đã thả. Nút "Kiểm tra" là một ô giữ tay 1 giây.

### 3.3 SkyShoot (lớp 3–5): nhảy bắn mũi tên
Trên trời có 3–4 đáp án trôi chậm. Một mũi tên quét qua lại liên tục. Bé nhảy thì mũi tên bắn đi. Trúng đáp án nào thì đáp án đó bị câu xuống. Bé làm động tác kéo dây hai tay luân phiên, 4 lần kéo, để kéo đáp án về (vừa vận động, vừa là bước xác nhận chống bắn nhầm). Sau đó game kiểm tra: đúng thì có animation chúc mừng (pháo hoa sao, Tin Tin nhảy múa); sai thì Tin Tin giải thích và đáp án rơi lại. Bắn trượt thì mũi tên quay về và tính một lượt, không trừ điểm; có tối đa 3 lượt bắn mỗi câu, hết lượt coi như sai.

Lớp 3–5 xen kẽ cả ba dạng (cùng một câu hỏi có thể được trình bày theo dạng khác nhau tùy bài).

## 4. Nội dung

- Nguồn: danh sách từ vựng và mẫu câu do ta tự soạn theo chủ đề từng unit của Global Success (từ vựng là dữ kiện; không sao chép văn bản sách). Một giáo viên hoặc chính người dùng rà soát một lần cho khớp sách.
- Cấu trúc sách đã xác nhận qua nguồn: lớp 1 và lớp 2 mỗi lớp 16 unit (kèm Review/Funtime ở lớp 2); lớp 3 có Starter + Unit 1–20 + 4 bài Review; lớp 4 có Starter + 20 unit + 4 Review; lớp 5 có Starter + Unit 1–20 (10 unit mỗi tập). Danh sách tên unit đầy đủ của từng lớp sẽ được đối chiếu với mục lục chính thức ở bước kế hoạch triển khai (chưa nhập vào đây để tránh ghi sai).
- Tiếng Anh là môn bắt buộc từ lớp 3; lớp 1–2 là chương trình làm quen, nên nội dung lớp 1–2 chỉ là nghe và nhận biết từ qua hình, không cần đánh vần.
- Định dạng dữ liệu: file JSON theo `grade/unit`, mỗi mục gồm `word`, `image`, `ttsText`, `sentencePatterns[]`, `distractors[]`, `modes[]`. Thêm unit chỉ cần thêm dữ liệu, không sửa code.
- Âm thanh: `flutter_tts` đọc bằng giọng tiếng Anh sẵn có trên máy. Nếu giọng trên máy nào đó quá tệ, dùng file âm thanh thu sẵn cho từ cốt lõi.

### Random hóa câu hỏi (chống học vẹt theo thứ tự)

Mỗi lần chơi lại một level phải ra bộ câu hỏi khác, để bé không thuộc đáp án theo vị trí hay thứ tự.

- **Ngân hàng câu hỏi lớn hơn số câu cần:** mỗi level có pool tối thiểu gấp 2 lần số câu của level (ví dụ level 1 cần 8 câu thì pool ≥ 16 mục), bốc ngẫu nhiên không lặp trong một lượt chơi.
- **Xáo trộn mọi thứ có thể xáo:** thứ tự câu hỏi, vị trí đáp án đúng giữa các làn/đáp án (không để đáp án đúng nằm cùng vị trí quá 2 câu liên tiếp), đáp án nhiễu bốc ngẫu nhiên từ cùng unit hoặc các unit đã học, thứ tự chữ cái bị xáo trong DragSpell (luôn kiểm tra không trùng thứ tự đúng), hướng và tốc độ mũi tên trong SkyShoot.
- **Tránh lặp giữa các lần chơi:** lưu cục bộ danh sách mục vừa được hỏi gần đây; lần chơi sau ưu tiên bốc các mục chưa hỏi hoặc lâu chưa hỏi. Chỉ khi pool cạn mới cho lặp lại.
- **Ôn lại câu sai:** mục bé trả lời sai được xếp lại vào cuối lượt chơi hiện tại (một lần), và có trọng số cao hơn ở lần chơi sau, nhưng không ở ngay câu kế tiếp.
- **Đổi cách hỏi cho cùng một từ:** cùng một mục có thể hỏi bằng nghe-chọn-hình, nhìn-hình-chọn-từ hoặc ghép chữ, tùy lớp và mode, để không học thuộc một dạng.
- **Kiểm thử:** bộ sinh câu hỏi nhận hạt giống ngẫu nhiên (seed) để kiểm thử lặp lại được; test kiểm tra không trùng câu trong một lượt, phân bố vị trí đáp án đúng, và không lặp lại ngay giữa hai lượt khi pool đủ lớn.

## 5. Level, thời gian và độ khó

Mỗi lớp có 5 level; áp dụng cho cả ba chế độ (số lượng làn/đáp án theo bảng).

| Level | Số câu | Thời gian mỗi câu | Số đáp án | Gợi ý hình | Nội dung |
|---|---|---|---|---|---|
| 1 Khởi động | 8 | 20 giây | 3 | Có | Từ vựng của 1 unit |
| 2 | 10 | 18 giây | 3 | Có | 1–2 unit |
| 3 | 10 | 15 giây | 4 | Ít | 2–3 unit |
| 4 | 12 | 12 giây | 4 | Không | Ôn các unit đã học |
| 5 Thử thách | 12 | 10 giây | 4 | Không | Trộn nhiều unit, từ/câu dài |

- Câu nhiều bước (ghép từ dài, sắp xếp câu, SkyShoot kèm kéo dây) được cộng thêm 50% thời gian.
- Mỗi level cho 1–3 sao theo tỉ lệ đúng: 1 sao từ 50%, 2 sao từ 75%, 3 sao từ 90%. 100 điểm mỗi câu đúng.
- Level N+1 mở khóa khi level N được ít nhất 1 sao. Cấu hình level nằm trong file riêng, tách khỏi nội dung.

## 6. Kiến trúc

Các khối độc lập, giao tiếp qua giao diện rõ ràng:

1. `input/` – PoseService, Calibration, bộ phát hiện sự kiện (lane, jump, hold, pull). Đầu ra là stream sự kiện chuẩn hóa. Có thể thay bằng nguồn giả (mock) để kiểm thử mà không cần camera.
2. `modes/` – LaneJump, DragSpell, SkyShoot; mỗi mode nhận một câu hỏi và các sự kiện, trả về kết quả đúng/sai.
3. `content/` – nạp JSON, sinh câu hỏi và đáp án nhiễu theo level, thực hiện random hóa (mục 4) và đọc/ghi lịch sử câu đã hỏi.
4. `levels/` – cấu hình level, bộ đếm giờ, tính điểm và sao.
5. `audio/` – TTS, hiệu ứng âm thanh, nhạc nền.
6. `mascot/` – các trạng thái hoạt hình của Tin Tin và hiệu ứng (nhún nhảy, pháo hoa sao, v.v.).
7. `progress/` – lưu tiến độ cục bộ.

**Xử lý lỗi:** mất theo dõi người chơi thì tạm dừng đồng hồ và hiện hướng dẫn; camera bị từ chối quyền thì hiện màn hình giải thích; TTS không khả dụng thì chuyển sang văn bản + âm thanh thu sẵn.

**Kiểm thử:** logic chế độ chơi và level kiểm thử bằng nguồn sự kiện giả; bộ phát hiện sự kiện kiểm thử bằng chuỗi landmark ghi sẵn; kiểm thử thủ công trên S24 Ultra cho độ trễ và độ chính xác.

## 7. Animation dễ thương

Tin Tin có các trạng thái: chờ, vui, buồn, cổ vũ, nhảy múa. Chữ cái nhún nhảy khi nhặt, ô trống phát sáng nhẹ khi tay tới gần, pháo hoa sao khi trúng đáp án, mây và sao trôi nhẹ ở nền, màn hình kết thúc level có Tin Tin trao sao. Mọi hiệu ứng ngắn (dưới 1,5 giây) để không làm chậm nhịp chơi.

## 8. Đồ họa: ba phương án (làm bằng Claude Design)

Cả ba dùng cùng mascot Tin Tin và cùng bộ màn hình để so sánh công bằng: (1) màn hình chính, (2) màn LaneJump lớp 1–2, (3) màn SkyShoot lớp 3–5, (4) màn DragSpell lớp 3–5, (5) màn kết quả level với sao.

- **Phương án A – "Khu vườn mây" (Sky Garden):** pastel mềm, trời xanh nhạt, mây bông, cây cỏ tròn trịa; cảm giác dịu mắt, hợp phụ huynh.
- **Phương án B – "Phi hành đoàn vũ trụ" (Space Cadets):** nền vũ trụ tím xanh đậm, hành tinh và sao hoạt hình; SkyShoot trở thành bắn sao băng; tương phản mạnh, đọc rõ khi chiếu TV.
- **Phương án C – "Thị trấn kẹo giấy" (Paper Candy Town):** phong cách giấy cắt dán nhiều lớp, màu kẹo rực rỡ, chuyển động kiểu stop-motion; nổi bật và dễ phân biệt với game toán.

Yêu cầu chung cho mọi phương án: chữ lớn, tương phản cao để đọc từ 2–3 m trên TV; vùng chạm/làn lớn; không đặt chi tiết quan trọng sát viền (an toàn khi cast); banner quảng cáo nhỏ ở một góc, không che gameplay. Nếu không dựng được trực tiếp trong Claude Design, mỗi phương án đi kèm một prompt đầy đủ để người dùng dán vào Design.

## 9. Giả định đã chọn

- Tên tạm: "Tin Tin English"; tên chính thức quyết định sau.
- Quản lý mã nguồn tại repo `avdoremon/g_english_motion` (riêng, không dùng chung `avdoremon/g_primary_math`); spec và kế hoạch nằm trong `docs/superpowers/` của repo này.
- Ngưỡng nhảy 12% và 4 lần kéo dây là giá trị khởi đầu, sẽ chỉnh sau spike đo đạc.
