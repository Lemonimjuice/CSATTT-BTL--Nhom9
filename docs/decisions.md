# Quy ước kỹ thuật chung

Các quyết định đã chốt cho hệ thống. Cập nhật lần cuối: 27/10/2026.

## D1. Nhánh làm việc

- `main` là nhánh chính, luôn ở trạng thái chạy được. Tính năng làm trên nhánh riêng rồi mở PR / fast-forward vào `main` sau khi `sh tests/demo/run-all.sh` đạt toàn bộ.

## D2. Kiến trúc: đúng 4 container, 2 mạng

- `nginx-waf`, `backend-node-1`, `backend-node-2`, `database`. Hai mạng `dmz_net` và `internal_net` (`internal: true`).
- Cụm API lỗi `/api/v1/vuln` chạy **ngay trên 2 node backend chính** (bật profile `sqli-lab` và `SQLI_DEMO_ENABLED=true`), song song với cụm vá `/api/v1/secure`. Dùng chung token, JWT secret và CSDL — khớp mục 3 đề cương.
- Dữ liệu cho phần SQLi nằm ở database `sqli_lab` **riêng trong cùng container `database`**, truy cập bằng tài khoản chỉ-đọc `sqli_demo_reader` (`database/init/04-sqli-demo.sh`). PostgreSQL không cho một câu lệnh truy vấn chéo database, nên SQLi ở cụm `/vuln` không chạm được bảng `public.users` của `blogdb`.
- `container_name` đặt đúng tên service (`backend-node-1`...) để lệnh demo trong đề cương chạy nguyên văn: `docker compose stop backend-node-1`.

## D3. Nginx + ModSecurity

- Image `owasp/modsecurity-crs:4.30.0-nginx-alpine-202610180210`, ghim thêm digest `sha256:873ce68a658d2e3b61484a8a24d215f7d15456e7ce5aec5e7114bf000d743365` (OWASP CRS 4.30.0, libmodsecurity 3.0.17, Nginx 1.30.6, Alpine 3.24.2). Tag để người đọc thấy phiên bản; digest để Docker tải đúng một bản trên mọi máy.
- Kiểm tra đã tải đúng bản: `docker images --digests owasp/modsecurity-crs`, so cột **DIGEST** với digest trên. Không so cột IMAGE ID: giá trị này khác nhau tùy chế độ lưu image của Docker (containerd hay bản cũ), dù cùng một image.
- Bỏ qua entrypoint sinh cấu hình của image; nhóm tự quản lý `nginx/nginx.conf` và `nginx/modsecurity/*` để cấu hình nằm trọn trong Git.
- Image chạy nginx bằng user không đặc quyền: nghe 8080/8443 trong container, compose map ra 80/443; `cap_drop: ALL`, `no-new-privileges`.
- `SecRuleEngine On` đặt trong `modsecurity.conf` (đúng TV2.2). Demo 3 ghi đè thành `DetectionOnly` qua file `mode/<WAF_MODE>.conf` nạp ngay sau đó.
- WAF chặn: Nginx trả `403` JSON kèm `X-Blocked-By: waf`. Backend không bao giờ đặt header này, nên phân biệt được với 403 phân quyền của backend.

## D4. Cặp vuln/secure (TV3.3)

| Lỗ hổng (đề cương mục 6) | Bản lỗi | Bản vá |
|---|---|---|
| SQL Injection (nối chuỗi) | `POST /api/v1/vuln/records/search` (reader DB sqli_lab) | `POST /api/v1/secure/records/search` (JPA tham số hóa) |
| Đọc bài nháp của người khác qua ID | `GET /api/v1/vuln/posts/{id}` | `GET /api/v1/secure/posts/{id}` → `403` |
| Lộ email tác giả | `/api/v1/vuln/posts/{id}` trả `author.email` | Response chỉ có `id, username, role` |
| Thiếu kiểm tra quyền (IDOR) | `PUT/DELETE /api/v1/vuln/posts/{id}` | `PUT/DELETE /api/v1/secure/posts/{id}` → `403` |
| Chưa đăng nhập trả 403 | — | `401` cho route cần xác thực |

Cụm `/secure/posts` dùng chung tầng Service (có Ownership Check) với route bài viết thường.

## D5. Header, IP thật và log tập trung (TV3.4)

- Nginx ghi đè `X-Forwarded-For`, `X-Real-IP` bằng `$remote_addr`.
- Backend (profile `integration`) bật `forward-headers-strategy: native` nhưng chỉ tin proxy có IP khớp `TRUSTED_PROXY_REGEX` (IP cố định của `nginx-waf`). Request từ nơi khác, kể cả header giả, vẫn ghi IP của socket.
- Nginx sinh `X-Request-ID` (`$request_id`), đồng thời đặt làm transaction ID của ModSecurity. Một mã đối chiếu được giữa log Nginx (`rid=`), `modsec_audit.log` (`unique_id`) và log backend (`reqId=`).
- **Audit log tập trung**: mọi log ghi ra thư mục `logs/` trên máy host: `logs/nginx/`, `logs/waf/modsec_audit.log`, `logs/backend-node-1/audit.log`, `logs/backend-node-2/audit.log`. Mẫu log backend có `reqId`, `user` và `ip` (IP client thật), gồm cả sự kiện đăng nhập, bị từ chối 401/403, sửa/xóa dữ liệu.
- `modsec_audit.log` (JSON) chỉ ghi phần A, H, K, Z: không có header và body request, nên không lộ JWT, mật khẩu.

## D6. WAF: chế độ, ngưỡng, luật tùy chỉnh

- `WAF_MODE=On` mặc định; `DetectionOnly` cho Demo 3 và dò false positive.
- Paranoia Level 1, ngưỡng anomaly 5 (một luật CRITICAL là chặn). Cho phép thêm `PUT`, `DELETE`.
- JSON Body Inspection: body `application/json` được phân tích JSON; mỗi trường thành `ARGS:json.<tên>`. Body JSON hỏng bị chặn `400`.
- **Đúng 2 luật tùy chỉnh** trong `custom-rules/nhom9-custom.conf` (TV2.3):
  - `100100`: vá ảo cho `/api/v1/vuln/records/search`, `keyword` chỉ được chứa chữ, số, khoảng trắng và `. , _ -`.
  - `100200`: `username` ở đăng nhập/đăng ký chỉ gồm `A-Z a-z 0-9 _ . @ -`.
- Ngoại lệ chống false positive cho `password`/`refreshToken` là tuning, đặt trong `crs-tuning.conf` (id 900500), không tính là luật tấn công.

## D7. Rate limiting

- Đăng nhập: 5 request/phút mỗi IP, burst 5.
- API chung: 5 request/giây, burst 10. Postman Runner và Burp Intruder nên đặt delay khoảng 300 ms.

## D8. Load balancing và failover

- Round-Robin, passive health check `max_fails=1 fail_timeout=15s`, `proxy_connect_timeout 1s`, `proxy_next_upstream error timeout http_502 http_503 http_504`.
- `resolver 127.0.0.11 valid=5s` + `resolve`: Nginx khởi động/restart được khi một node đang tắt và tự nhận node khi nó bật lại với IP mới.

## D9. Chứng chỉ

- Mỗi máy tự sinh bằng `sh nginx/certs/generate-cert.sh` (SAN `DNS:localhost, IP:127.0.0.1`, 365 ngày). Khóa không commit.

## D10. Khởi tạo CSDL

- `database/init/` mount vào `/docker-entrypoint-initdb.d/`: `01-schema.sql`, `02-least-privilege.sql`, `03-seed-data.sql`, `04-sqli-demo.sh` (tạo database `sqli_lab` + reader).
- Chỉ chạy khi volume trống; sửa SQL/SH xong phải `docker compose down -v`.
- `.gitattributes` ép LF cho `*.sql`, `*.sh`, `*.conf`, `*.yml` (psql/shell đọc sai khi dòng kết thúc bằng CRLF).
- Backend nghiệp vụ kết nối bằng `app_user`: không superuser, không quyền CREATE trên schema.
