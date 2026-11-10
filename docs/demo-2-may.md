# Demo trên 2 máy: một máy tấn công, một máy nạn nhân trong mạng LAN

Cả 2 máy chạy Windows, cùng một mạng.

- **Máy nạn nhân** chạy toàn bộ hệ thống (Docker Desktop: `nginx-waf`, 2 node backend, database), thao tác
  phía phòng thủ (tắt node, đổi chế độ WAF) và mở cửa sổ xem log để thấy hệ thống phản ứng.
- **Máy tấn công** không cần Docker: chỉ gửi request qua mạng tới `https://<IP máy nạn nhân>` bằng Burp Suite,
  Postman, trình duyệt, hoặc script `tests/lan/attacker.sh` (cần Git Bash và bản clone repo).

Chỉ cổng 443 mở ra mạng; backend (8080) và database không mở, máy tấn công tự kiểm chứng được điều này.

## 1. Chuẩn bị máy nạn nhân

1. Mở Docker Desktop, chờ biểu tượng chuyển xanh. Trong Git Bash, tại thư mục repo:

   ```bash
   docker compose up -d --build --wait
   ```

   ```bash
   sh scripts/preflight.sh
   ```

2. Bấm đúp `scripts\Xem-Log.bat`. Đầu cửa sổ in địa chỉ để máy tấn công gọi tới (dòng có `Wi-Fi` hoặc
   `Ethernet`, ví dụ `https://192.168.100.193`) và chế độ WAF hiện tại. Để cửa sổ này mở suốt buổi demo
   (chiếu lên cho thầy xem).
3. Mạng: 2 máy cùng Wi-Fi/hotspot. Wi-Fi công cộng (trường, quán) thường chặn các máy nói chuyện với nhau;
   khi đó dùng hotspot điện thoại hoặc router riêng. IP có thể đổi mỗi lần kết nối lại, nên xem lại trước khi demo.
4. Tường lửa: khi cài, Docker Desktop đã tạo luật cho phép `Docker Desktop Backend` nhận kết nối. Nếu máy tấn
   công không vào được, kiểm tra luật này trong Windows Defender Firewall (cho cả mạng Public và Private).
5. Chỉ để chạy 4 container của hệ thống. Container của project khác có publish cổng (ví dụ bản mã nguồn gốc
   chạy ở cổng 8080, PostgreSQL ở 5432) cũng lộ ra mạng LAN, làm sai kiểm chứng "chỉ mở 443". Xem bằng
   `docker ps` và dừng container không thuộc hệ thống trước buổi demo.

File bấm đúp cho máy nạn nhân (tất cả trong `scripts\`, không cần Git Bash):

| File | Dùng khi |
|---|---|
| `Xem-Log.bat` | Mở đầu buổi: xem log Nginx, WAF, backend theo thời gian thực |
| `Tra-RequestID.bat` | Dán mã `X-Request-ID` mà máy tấn công đọc được, xem request đó đi tới lớp nào |
| `Demo1-TatNode1.bat` / `Demo1-BatNode1.bat` | Demo 1: đánh sập / bật lại `backend-node-1` |
| `WAF-DetectionOnly.bat` / `WAF-On.bat` | Demo 3: WAF chỉ ghi log / chặn trở lại |

Màu trong cửa sổ log: xanh lá = cho qua, vàng = bị từ chối 401/403 hoặc WAF đang DetectionOnly, đỏ = WAF chặn,
tím = rate limit 429, xám = cảnh báo nhẹ. Cột `rid=` (8 ký tự đầu của request ID) giúp dò cùng một request qua 3 lớp.

Khi máy tấn công gọi bằng địa chỉ IP, mọi request đều có thêm dòng WAF xám "cảnh báo nhẹ 920350": luật OWASP CRS
920350 đánh dấu Host header là địa chỉ IP (kiểu máy quét tự động hay dùng). Luật này chỉ cộng điểm thấp, dưới
ngưỡng chặn, nên request hợp lệ vẫn đi tiếp; đây là hành vi bình thường của CRS, có thể dùng làm ví dụ WAF quan
sát cả những dấu hiệu nhỏ.

## 2. Chuẩn bị máy tấn công

1. Mở trình duyệt vào `https://<IP máy nạn nhân>/actuator/health`. Trình duyệt cảnh báo chứng chỉ (chứng chỉ
   tự ký, chỉ ghi tên `localhost`): chọn Nâng cao > Tiếp tục. Thấy `{"status":"UP"}` là kết nối được.
2. **Burp Suite**: Target `https://<IP máy nạn nhân>:443`, dùng các request mẫu trong `tests/burp/`
   (xem [tests/burp/README.md](../tests/burp/README.md)). Burp không kiểm tra chứng chỉ nên không bị lỗi.
3. **Postman**: import `tests/postman/Nhom9-DefenseInDepth.postman_collection.json` và môi trường
   `tests/postman/Nhom9-LAN.postman_environment.json`, sửa `baseUrl` thành `https://<IP máy nạn nhân>`.
   Tắt Settings > General > SSL certificate verification (chứng chỉ tự ký không ghi IP của máy nạn nhân).
4. **Script** (tùy chọn, để tập dượt nhanh hoặc cho Claude chạy): cần Git Bash và bản clone repo.

   ```bash
   sh tests/lan/attacker.sh 192.168.100.193 check
   ```

   Thay `192.168.100.193` bằng IP máy nạn nhân. `check` kiểm tra HTTPS 443, cổng 80 và 8080 đóng, đăng nhập được.

## 3. Kịch bản từng demo

Làm theo thứ tự; brute-force **để cuối** vì sau đó đăng nhập bị chặn khoảng 1 phút (tính chung cho mọi máy).

| Demo | Máy tấn công | Máy nạn nhân | Thấy gì |
|---|---|---|---|
| 1. HA & Failover | Đăng nhập user_a, gọi `GET /api/v1/posts/me` liên tục bằng token đó | Đang có request thì bấm `Demo1-TatNode1.bat`; xong bấm `Demo1-BatNode1.bat` | Máy tấn công vẫn nhận `200`, không phải đăng nhập lại. Cửa sổ log: dòng NGINX có `upstream=` 2 địa chỉ (failover) |
| 2. Vá ảo | Burp gửi `' OR '1'='1` vào `/api/v1/vuln/records/search` | WAF ở chế độ On; dán `X-Request-ID` vào `Tra-RequestID.bat` | `403`, header `X-Blocked-By: waf`. Log: WAF **CHẶN**, luật `100100`; không có dòng NODE (request không tới backend) |
| 3. Defense in Depth | Gửi cùng payload vào `/api/v1/vuln/...` và `/api/v1/secure/...` | Trước đó bấm `WAF-DetectionOnly.bat`; xong **bắt buộc** bấm `WAF-On.bat` | Bản lỗi lộ 3 dòng, bản vá trả `[]`. Log: WAF **PHÁT HIỆN (không chặn)**, backend vẫn xử lý an toàn |
| 4. IDOR | user_b gửi GET/PUT/DELETE `/api/v1/secure/posts/3` (bài nháp của user_a); gửi lại không kèm token | Xem cửa sổ log | `403` không có `X-Blocked-By` (backend chặn, WAF cho qua); không token `401`. Log NODE: `user=user_b ... -> 403` |
| Bổ sung | Gửi `X-Forwarded-For: 6.6.6.6`; thử `/swagger-ui/index.html`, `/actuator/env`, cổng 80, 8080; cuối cùng Intruder đoán mật khẩu | Tra request ID của request giả IP | `6.6.6.6` không có trong log; Swagger/actuator `404`; cổng 80, 8080 đóng; brute-force bị `429` |

Bản lỗi `/api/v1/vuln/posts` sửa dữ liệu thật; đừng xóa bài 3. Lỡ xóa thì trên máy nạn nhân chạy
`sh scripts/reset-demo.sh --yes`.

## 4. Chạy tự động để tập dượt

Trên máy tấn công (Git Bash):

```bash
sh tests/lan/attacker.sh 192.168.100.193 all
```

Script chạy `check`, rồi Demo 1 đến 5 và in `PASS`/`FAIL`. Tới bước cần máy nạn nhân, script in dòng
`>>> MÁY NẠN NHÂN: ...` và tự đợi (tối đa 120 giây, đổi bằng biến `WAIT_MAX`), không cần bấm Enter:

- Demo 1: gửi mỗi giây 1 request; khi thấy Nginx chuyển node thì tự đi tiếp, rồi đợi node 1 được bật lại.
- Demo 3: tự phát hiện WAF đã sang DetectionOnly (payload lọt qua), rồi đợi WAF bật lại (payload bị chặn).

Có thể chạy riêng từng phần: `check`, `demo1` ... `demo5`. Trên máy nạn nhân vẫn chạy được bộ đầy đủ
`sh tests/demo/run-all.sh` (tự làm cả phần phòng thủ) để kiểm tra hệ thống trước buổi demo.

Nếu mỗi máy có một phiên Claude Code: phiên ở máy nạn nhân dựng hệ thống, chạy `preflight.sh` và
`run-all.sh`, làm các bước phía nạn nhân; phiên ở máy tấn công chạy `attacker.sh`. Hai phiên không tự
liên lạc với nhau, người điều phối báo cho phiên máy nạn nhân khi script máy tấn công in `>>> MÁY NẠN NHÂN`.

## 5. Hạn chế đã biết: log không ghi IP của máy tấn công

Docker Desktop trên Windows chạy container trong một máy ảo ẩn. Kết nối từ máy tấn công tới cổng 443 được
chương trình của Docker Desktop nhận rồi mở kết nối mới vào container, nên Nginx thấy địa chỉ nguồn là IP
cổng mạng Docker (ví dụ `172.21.0.1`) thay vì IP máy tấn công. Hệ quả:

- Log Nginx, audit log WAF và audit log backend ghi `172.21.0.1` cho mọi máy.
- Rate limit theo IP tính chung cho mọi máy (máy nạn nhân cũng bị `429` sau khi máy tấn công brute-force).

Cấu hình của nhóm vẫn đúng: Nginx ghi `$remote_addr` và đặt `X-Forwarded-For` bằng IP mà nó thấy; backend
chỉ tin `X-Forwarded-For` từ IP của Nginx (`10.209.10.10`), nên client không tự điền IP giả được (bổ sung
kiểm chứng với `6.6.6.6`). Chạy cùng cấu hình trên Linux với Docker Engine (không phải Docker Desktop),
Docker giữ nguyên IP nguồn và log ghi đúng IP máy tấn công. Nhóm dùng Docker Desktop trên Windows vì cả
2 máy demo đều chạy Windows.

## 6. Sự cố thường gặp

| Hiện tượng | Cách xử lý |
|---|---|
| Máy tấn công không mở được `https://<IP>/actuator/health` | Kiểm tra cùng mạng (thử `ping <IP>`), đúng IP (xem đầu cửa sổ `Xem-Log.bat`), máy nạn nhân đang chạy hệ thống, tường lửa (mục 1) |
| Mọi request trả `401` | Token hết hạn sau 15 phút: đăng nhập lại |
| Đăng nhập bị `429` | Vừa brute-force hoặc đăng nhập quá 5 lần/phút; chờ khoảng 1 phút |
| Demo 2 không bị chặn | WAF còn ở DetectionOnly từ Demo 3: bấm `WAF-On.bat` |
| Demo 1 trả lỗi khi node tắt | Kiểm tra node 2 còn chạy (`docker compose ps` trên máy nạn nhân) |
| `attacker.sh` báo cổng 8080 không đóng | Máy nạn nhân đang chạy container khác publish cổng 8080 (xem `docker ps`); dừng nó (mục 1, bước 5) |
