# Checklist trình bày và xử lý sự cố

Mọi lệnh chạy trong **Git Bash** (cài cùng Git for Windows: chuột phải thư mục repo > *Open Git Bash here*),
không chạy trong PowerShell hay CMD. Trên macOS/Linux dùng terminal bình thường.

## Trước buổi trình bày (ở nhà, có Internet)

- [ ] `git pull origin main`, rồi `sh scripts/init-env.sh` và `sh nginx/certs/generate-cert.sh`.
- [ ] `docker compose up -d --build --wait`. Lần đầu cần Internet để tải image và thư viện Maven; Docker Hub
      giới hạn lượt tải ẩn danh theo IP, nên **đừng để tới lúc dùng mạng trường mới tải**.
- [ ] `sh tests/demo/run-all.sh` đạt toàn bộ.
- [ ] Không chạy `docker system prune` sau đó (sẽ xóa image đã tải, buổi trình bày lại cần Internet).
- [ ] Đóng các chương trình đang chiếm cổng 443 (IIS, XAMPP, Skype bản cũ, stack Docker khác).

## Ngay trước khi trình bày (10 phút)

- [ ] `sh scripts/reset-demo.sh --yes`: dựng lại sạch (dữ liệu mẫu gốc, log trống) và tự chạy preflight.
- [ ] `sh scripts/preflight.sh` không còn dòng `[FAIL]`. `[WARN]` thì đọc gợi ý ngay bên dưới dòng đó.
- [ ] Mở Burp/Postman, thêm `nginx/certs/server.crt` làm chứng chỉ tin cậy (hoặc tắt kiểm tra SSL).
- [ ] Tắt các stack Docker không liên quan để máy nhẹ hơn.

## Trong lúc trình bày

| Lưu ý | Vì sao |
|---|---|
| Đăng nhập lại ngay trước mỗi demo | Access token hết hạn sau **15 phút**; token cũ trả `401`, dễ nhầm là failover hỏng hoặc chưa đăng nhập |
| Để demo brute-force (rate limit) **cuối cùng** | Burp, Postman, trình duyệt trên cùng máy dùng chung hạn mức đăng nhập 5 lần/phút; sau brute-force phải chờ khoảng 1 phút |
| Sau Demo 1, bật lại node: `docker compose start backend-node-1` | Script demo tự bật lại; làm tay thì phải nhớ |
| Demo 3 đổi chế độ WAF bằng `sh scripts/waf-mode.sh DetectionOnly`, xong thì `sh scripts/waf-mode.sh On` | Quên bật lại thì WAF chỉ ghi log, không chặn Demo 2 |
| Bản lỗi `/api/v1/vuln/posts` sửa/xóa **dữ liệu thật** | Đừng xóa bài 3 (Demo 4 dùng bài này); lỡ xóa thì `sh scripts/reset-demo.sh --yes` |
| Gõ tiếng Việt qua Postman/Burp/trình duyệt, không gõ thẳng trong `curl` trên terminal Windows | Terminal có thể gửi sai mã hóa, WAF trả `400 Failed to parse request body` (đúng là WAF chặn JSON hỏng) |
| Tìm kiếm có dấu ở `/api/v1/vuln/records/search` bị WAF chặn `403` | Cố ý: luật vá ảo 100100 chỉ cho chữ không dấu, số và `. , _ -` |
| Log ghi giờ UTC | Giờ Việt Nam = giờ trong log + 7. Log backend ghi kèm `Z` (UTC); log Nginx ghi `+0000` |
| Tấn công từ **máy khác** trong mạng LAN | Docker Desktop (Windows/macOS) thường không giữ IP nguồn: Nginx thấy mọi máy là cùng một IP cổng Docker (vd. `172.21.0.1`), log và rate limit gộp chung. Demo từ chính máy chạy hệ thống thì không ảnh hưởng |

## Sau khi trình bày: lấy minh chứng

Log nằm sẵn trong `logs/` (xem [test-evidence/README.md](test-evidence/README.md)). Tra một request WAF:
`sh scripts/waf-audit.sh <X-Request-ID>`.

## Xử lý sự cố

| Triệu chứng | Nguyên nhân thường gặp | Cách sửa |
|---|---|---|
| `docker compose up` báo `Đặt ... trong .env` | `.env` từ bản cũ, thiếu biến | Xóa `.env`, chạy `sh scripts/init-env.sh`, rồi `docker compose down -v` |
| Backend không healthy, log có `SQLi lab isolation check failed` | Volume DB từ bản cũ, chưa có database `sqli_lab` | `sh scripts/reset-demo.sh --yes` |
| Backend báo `JWT_SECRET must be Base64...` | `JWT_SECRET` không phải Base64 >= 32 byte | Sinh lại `.env` bằng `sh scripts/init-env.sh` |
| Gọi `/api/v1/secure/posts` trả `404` | Đang chạy image backend cũ | `docker compose up -d --build --wait` (luôn kèm `--build` sau khi pull) |
| `port is already allocated` / `bind: address already in use` (443) | Ứng dụng khác đang chiếm cổng 443 | Tắt ứng dụng đó hoặc stack Docker khác |
| `Conflict. The container name "/database" is already in use` | Project Docker khác dùng trùng tên container | `docker rm -f database` (nếu đó là container không cần) hoặc dừng project kia |
| `Pool overlaps with other one on this address space` | Mạng VPN/công ty trùng dải `10.209.10.0/24` | Tắt VPN khi chạy demo |
| Trên Linux: Nginx dừng với `Permission denied` | Thư mục `logs/` do Docker tạo thuộc root, hoặc khóa chứng chỉ quyền 600 | `sh scripts/init-env.sh` và `FORCE=1 sh nginx/certs/generate-cert.sh`, rồi `docker compose up -d` |
| Đăng nhập trả `429` | Vừa chạy brute-force hoặc đăng nhập quá nhiều | Chờ khoảng 1 phút |
| Request hợp lệ trả `401` giữa buổi | Access token hết hạn (15 phút) | Đăng nhập lại |
| `http://localhost` không vào được | Cổng 80 không mở (đề cương chỉ mở 443) | Dùng `https://localhost` |
