# Hướng dẫn thực hành và trình bày demo (cho cả nhóm)

Tài liệu này để **cả nhóm tập dượt** và **đứng lớp chạy demo cho thầy**: ai ngồi máy nào, bấm gì,
thao tác Burp/Postman từng bước, thầy sẽ thấy gì. Người chưa quen công cụ vẫn làm theo được.

Đọc kèm: [demo-2-may.md](demo-2-may.md) (dựng hệ thống 2 máy), [demo-checklist.md](demo-checklist.md)
(checklist nhanh), [../tests/burp/README.md](../tests/burp/README.md) (request mẫu Burp).

Mô hình: **một máy tấn công** và **một máy nạn nhân** trong cùng mạng. Máy nạn nhân chạy hệ thống
(Docker), máy tấn công gửi đòn tấn công bằng Burp/Postman. Trong tài liệu, thay `<IP>` bằng địa chỉ
thật của máy nạn nhân (hiện ở đầu cửa sổ `Xem-Log.bat`, ví dụ `192.168.100.193`).

---

## 0. Phân vai: ai ngồi máy nào

| Vai | Ngồi máy | Việc chính khi demo |
|---|---|---|
| **Người giữ hệ thống** (hợp TV1/TV2) | Máy nạn nhân | Mở cửa sổ log, bấm các file `.bat` khi tới lượt (tắt node, đổi WAF), chỉ cho thầy thấy log |
| **Người tấn công** (hợp TV4) | Máy tấn công | Dùng Burp và Postman gửi đòn tấn công, đọc kết quả trên màn hình |
| **Người thuyết minh** (hợp TV3) | Đứng nói | Giải thích mỗi demo chứng minh điều gì, đọc kết quả |
| **Người ghi chú** | Tùy | Theo checklist, nhắc bước tiếp theo, chụp màn hình minh chứng |

Nhóm ít người thì một người kiêm nhiều vai. Quan trọng là **người giữ hệ thống** và **người tấn công**
ngồi hai máy khác nhau.

---

## 1. Cài đặt một lần trên mỗi máy

### Máy nạn nhân (máy chạy hệ thống)
1. Cài **Docker Desktop**, **Git for Windows** (có Git Bash).
2. Clone repo, chuyển sang nhánh có code mới nhất:
   ```bash
   git clone -b main-2 https://github.com/Lemonimjuice/CSATTT-BTL--Nhom9.git
   ```
3. Lần đầu cần Internet để tải image và thư viện.

### Máy tấn công
1. Cài **Git for Windows** (để chạy script kiểm tra nhanh) và clone repo như trên (để có sẵn file mẫu Burp,
   Postman).
2. Cài **Burp Suite Community Edition** (bản miễn phí, tải ở portswigger.net). Cần có Java; bản cài sẵn
   đã kèm.
3. Cài **Postman** (bản desktop, miễn phí).

---

## 2. Mỗi lần bắt đầu (cả buổi tập lẫn buổi thi) — khoảng 5 phút

### Trên máy nạn nhân
1. Mở Docker Desktop, chờ biểu tượng xanh.
2. Git Bash, tại thư mục repo:
   ```bash
   docker compose up -d --build --wait
   ```
   ```bash
   sh scripts/preflight.sh
   ```
   Phải thấy dòng cuối `... 0 FAIL`. Nếu có `FAIL`, làm theo gợi ý in kèm.
3. Nếu máy có chạy project Docker khác mở cổng ra ngoài (xem `docker ps`), **dừng chúng** để không lẫn
   với hệ thống (giữ đúng "chỉ mở 443"):
   ```bash
   docker stop <tên-container-lạ>
   ```
4. Bấm đúp **`scripts\Xem-Log.bat`**. Đầu cửa sổ in **địa chỉ `<IP>`** để máy tấn công gọi tới. Để cửa
   sổ này mở suốt buổi, chiếu lên cho thầy xem.

### Trên máy tấn công
1. Mở trình duyệt vào `https://<IP>/actuator/health`. Lần đầu trình duyệt cảnh báo chứng chỉ (vì là
   chứng chỉ tự ký) → Nâng cao → Tiếp tục. Thấy `{"status":"UP"}` là kết nối được.
2. (Nên làm) Git Bash kiểm tra nhanh toàn tuyến:
   ```bash
   sh tests/lan/attacker.sh <IP> check
   ```
   Đủ 4 `PASS` là sẵn sàng. Nếu cổng 8080 `FAIL`, báo máy nạn nhân dừng project lạ (bước 3 ở trên).

---

## 3. Dùng Burp Suite (từng bước, cho người mới)

Burp dùng để **gửi một request và xem kết quả**, giống gửi một lá đơn rồi đọc thư trả lời. Ta dùng hai
công cụ trong Burp: **Repeater** (gửi lại một request, dùng cho hầu hết demo) và **Intruder** (gửi nhiều
lần, dùng cho brute-force).

### 3.1. Mở Burp
1. Mở Burp Suite Community → **Next** → **Start Burp** (chọn "Temporary project", mặc định là được).
2. Lên thanh tab, chọn **Repeater**.

### 3.2. Gửi một request bằng Repeater
1. Mở file mẫu trong `tests/burp/` bằng Notepad, ví dụ `10-demo2-sqli-vuln.http`. **Copy toàn bộ** nội dung.
2. Trong Burp, tab **Repeater**: bấm vào ô request (khung bên trái), xóa nội dung cũ, **dán** request vừa copy.
3. Đặt đích đến: bấm nút **Target** ở góc trên tab Repeater (hoặc biểu tượng bút chì) → điền
   **Host = `<IP>`**, **Port = `443`**, tích **Use HTTPS** → OK. (Dòng `Host: localhost` trong request cứ
   để nguyên, Nginx vẫn nhận.)
4. Bấm **Send**. Khung bên phải hiện thư trả lời. Dòng đầu là **mã trạng thái**, ví dụ `HTTP/1.1 403 Forbidden`.

Đọc mã trạng thái: `200` = cho qua, `401` = chưa đăng nhập, `403` = bị từ chối/chặn, `429` = bị giới hạn
tần suất, `400` = request sai.

### 3.3. Lấy token để gửi request cần đăng nhập
Một số request có dòng `Authorization: Bearer <TOKEN_USER_A>`. Phải thay `<TOKEN_USER_A>` bằng token thật:
1. Repeater: dán và gửi `01-login-user-a.http` (đổi Target như trên). Thư trả lời là một đoạn JSON có
   `"accessToken":"eyJ..."`. **Copy chuỗi dài** giữa hai dấu `"` của `accessToken` (không lấy dấu ngoặc).
2. Mở request cần token (ví dụ `20-demo4-idor-read-secure.http` dùng `<TOKEN_USER_B>` → phải login user_b
   bằng `02-login-user-b.http`). Thay cả cụm `<TOKEN_USER_A>` (hoặc `<TOKEN_USER_B>`) bằng chuỗi token
   vừa copy, rồi **Send**.
3. Token sống **15 phút**. Hết giờ thì gửi lại request login để lấy token mới.

### 3.4. Brute-force (cách dễ, không cần Intruder)
1. Repeater: dán `30-bruteforce-login.http`, nhưng sửa `§guess§` thành một mật khẩu sai bất kỳ, ví dụ `sai123`.
2. Bấm **Send** nhanh khoảng 8 lần liên tiếp (trong vòng ~10 giây). Khoảng 5–6 lần đầu trả `401` (sai
   mật khẩu), sau đó trả **`429`** (bị chặn vì quá 5 lần/phút). Bấm chậm quá (cách nhau hơn 10 giây) thì
   hạn mức hồi lại, khó thấy `429`.
3. Làm demo này **cuối cùng**, vì sau đó đăng nhập bị chặn khoảng 1 phút.

### 3.5. Brute-force bằng Intruder (tùy chọn, nhìn "chuyên" hơn)
1. Ở request login, bôi đen chỗ mật khẩu, bấm chuột phải → **Send to Intruder**.
2. Tab **Intruder** → **Positions**: Burp đã đánh dấu chỗ mật khẩu bằng `§...§`.
3. **Payloads**: nhập danh sách mật khẩu đoán (mỗi dòng một mật khẩu) → **Start attack**.
4. Bản Community chạy chậm (giới hạn tốc độ), nhưng vẫn thấy cột Status chuyển từ `401` sang `429`.

---

## 4. Dùng Postman (từng bước)

Postman dễ hơn Burp: đã có sẵn bộ request, chỉ việc bấm **Send**. Bộ này **tự lưu token** sau khi đăng
nhập nên không phải copy tay.

### 4.1. Cài đặt lần đầu
1. Mở Postman → **Import** → chọn 2 file:
   - `tests/postman/Nhom9-DefenseInDepth.postman_collection.json` (bộ request)
   - `tests/postman/Nhom9-LAN.postman_environment.json` (môi trường cho LAN)
2. Góc trên bên phải, chọn môi trường **"Nhóm 9 - LAN (máy tấn công)"**.
3. Bấm biểu tượng con mắt cạnh ô môi trường → sửa **`baseUrl`** thành `https://<IP>` (thay IP thật) → Save.
4. Tắt kiểm tra chứng chỉ: **Settings** (bánh răng) → **General** → tắt **SSL certificate verification**.
   (Vì chứng chỉ của lab là tự ký.)

### 4.2. Chạy
- **Cách 1 (từng request, dễ theo dõi):** mở thư mục **0. Auth** → chạy **Login User A** và **Login User B**
  trước (token tự lưu). Sau đó mở các request khác, bấm **Send**, đọc mã trạng thái và nội dung trả về.
- **Cách 2 (chạy cả loạt):** bấm **...** cạnh tên collection → **Run collection** → đặt **Delay 300 ms**
  (tránh chạm giới hạn tần suất) → **Run**. Postman chạy toàn bộ và báo pass/fail từng request.

Mỗi request đã đặt tên kèm kết quả mong đợi (ví dụ "B sửa bài của A -> 403"), nên nhìn tên là biết đúng/sai.

---

## 5. Đọc cửa sổ log trên máy nạn nhân

Cửa sổ `Xem-Log.bat` hiện mỗi request mới theo thời gian thực, ghép cả 3 lớp: `NGINX`, `WAF`, `NODE-1/2`
(backend). Màu:

| Màu | Nghĩa |
|---|---|
| Xanh lá | Cho qua (200) |
| Vàng | Bị từ chối 401/403, hoặc WAF đang DetectionOnly (chỉ ghi, không chặn) |
| Đỏ | WAF chặn |
| Tím | Bị giới hạn tần suất (429) |
| Xám | Cảnh báo nhẹ, dưới ngưỡng, vẫn cho qua |

**Mã rid**: mỗi response có header `X-Request-ID`. Cùng mã đó xuất hiện ở cả 3 lớp, nên lần theo được một
request. Muốn tra một request: bấm đúp **`scripts\Tra-RequestID.bat`**, dán mã (đọc trong Burp/Postman ở
header `X-Request-ID`). Cửa sổ in request đó đã đi tới lớp nào và kết luận (ví dụ: WAF chặn, không tới backend).

---

## 6. Kịch bản 4 demo khi đứng lớp

Mỗi demo: **người thuyết minh** nói một câu, **người tấn công** thao tác, **người giữ hệ thống** làm phần
của mình, rồi cùng chỉ vào kết quả. Làm theo thứ tự 1 → 4, brute-force để cuối.

### Demo 1 — Sẵn sàng cao (Failover)
- **Nói:** "Tắt một máy chủ, hệ thống vẫn phục vụ nhờ máy còn lại, người dùng không phải đăng nhập lại."
- **Máy tấn công:** Postman gửi lặp lại **GET /posts/me của A** (cần token A), hoặc Git Bash chạy
  `sh tests/lan/attacker.sh <IP> demo1`.
- **Máy nạn nhân:** khi request đang chạy, bấm đúp **`scripts\Demo1-TatNode1.bat`**; xong bấm **`Demo1-BatNode1.bat`**.
- **Thầy thấy:** request vẫn trả `200`; trong log Nginx có dòng `upstream=` hai địa chỉ = đã thử node sập
  rồi chuyển sang node kia.

### Demo 2 — Vá ảo tại WAF
- **Nói:** "Gửi SQL Injection, WAF chặn ngay ở cửa, code bên trong không hề nhận được."
- **Máy tấn công:** Burp Repeater gửi `10-demo2-sqli-vuln.http` (cần token A).
- **Thầy thấy:** `403`, header `X-Blocked-By: waf`. Trên log máy nạn nhân: dòng WAF **CHẶN**, luật `100100`,
  **không** có dòng backend. (Tra bằng `Tra-RequestID.bat` với mã trong `X-Request-ID`.)

### Demo 3 — Phòng thủ chiều sâu
- **Nói:** "Giả sử WAF bị lách. Bản code lỗi sẽ lộ dữ liệu, còn bản code vá vẫn an toàn nhờ truy vấn tham số hóa."
- **Máy nạn nhân:** bấm đúp **`scripts\WAF-DetectionOnly.bat`** (WAF chỉ ghi log, không chặn).
- **Máy tấn công:** Burp gửi `12-demo3-sqli-vuln-detection.http` (bản lỗi) → lộ 3 dòng; rồi gửi
  `11-demo2-sqli-secure.http` (bản vá) → trả `[]` rỗng.
- **Máy nạn nhân:** xong demo, **bắt buộc** bấm **`scripts\WAF-On.bat`** để chặn trở lại.
- **Thầy thấy:** cùng một đòn, bản lỗi lộ dữ liệu, bản vá không lộ gì.

### Demo 4 — Chống IDOR (vượt quyền)
- **Nói:** "User B đăng nhập hợp lệ nhưng cố sửa bài của User A. WAF cho qua vì không có ký tự độc hại,
  nhưng tầng ứng dụng đối chiếu chủ sở hữu và chặn."
- **Máy tấn công:** Burp gửi (cần token B) `20/21/22-demo4-*.http` → đều `403`; gửi `23-demo4-no-token.http`
  (không token) → `401`. Đối chứng bản lỗi: `24/25-demo4-*-vuln.http` → `200`, đọc/sửa được bài của A, lộ email.
- **Thầy thấy:** bản vá chặn `403`/`401`; log backend ghi `user=user_b ... -> 403`.

### Brute-force (để cuối)
- **Nói:** "Đoán mật khẩu nhiều lần sẽ bị khóa tạm."
- **Máy tấn công:** mục 3.4 (Burp) hoặc Postman "Sai mật khẩu" chạy nhiều lần.
- **Thầy thấy:** vài lần `401` rồi `429`.

---

## 7. Phân công lúc trình bày (một mạch)

1. **Người giữ hệ thống** mở sẵn `Xem-Log.bat`, chiếu màn hình log.
2. **Người thuyết minh** giới thiệu kiến trúc (xem [README](../README.md)), rồi dẫn từng demo.
3. Mỗi demo: thuyết minh nói → tấn công bấm Send → giữ hệ thống bấm `.bat` (nếu cần) → cùng chỉ kết quả.
4. **Người ghi chú** nhắc "token còn hạn không", "đã bật lại WAF chưa", và chụp màn hình minh chứng.

---

## 8. Sự cố hay gặp

| Hiện tượng | Xử lý |
|---|---|
| Mọi request `401` | Token hết hạn (15 phút): gửi lại request login lấy token mới |
| Đăng nhập `429` | Vừa brute-force hoặc quá 5 lần/phút: chờ khoảng 1 phút |
| Demo 2 không bị chặn | WAF còn ở DetectionOnly: bấm `WAF-On.bat` |
| Máy tấn công không vào được `<IP>` | Kiểm tra 2 máy cùng mạng, đúng IP, hệ thống đang chạy, tường lửa (xem demo-2-may.md mục 1) |
| Bài 3 bị sửa/xóa sau khi tập | Máy nạn nhân chạy `sh scripts/reset-demo.sh --yes` để về dữ liệu gốc |
| Burp báo lỗi chứng chỉ | Burp mặc định bỏ qua; nếu chặn, Repeater vẫn gửi được tới chứng chỉ tự ký |

**Hạn chế cần nêu khi báo cáo:** IP trong log là IP cổng mạng Docker (`172.21.0.1`), không phải IP máy
tấn công — do Docker Desktop trên Windows không giữ IP nguồn. Chi tiết: [demo-2-may.md](demo-2-may.md) mục 5.

---

## 9. Lịch tập gợi ý

- **Buổi 1:** dựng hệ thống trên máy nạn nhân, chạy `attacker.sh all` để thấy toàn cảnh; mỗi người đọc hiểu
  một demo chứng minh điều gì.
- **Buổi 2:** làm tay Demo 2 và Demo 4 bằng Burp, Demo bất kỳ bằng Postman; tập lấy token, đọc mã trạng thái.
- **Buổi 3 (tổng duyệt):** chạy một mạch 4 demo + brute-force như thật, bấm giờ, phân vai cố định, chụp đủ
  ảnh minh chứng.
