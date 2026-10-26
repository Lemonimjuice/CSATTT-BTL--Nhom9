# Quy ước kỹ thuật chung

Các quyết định đã chốt cho hệ thống. Cập nhật lần cuối: 27/10/2026.

## D1. Nhánh làm việc

- `integration/v2` là nhánh tích hợp; tính năng làm trên nhánh riêng tách từ đó rồi mở PR vào `integration/v2`.
- Chỉ merge `integration/v2` vào `main` khi `sh tests/demo/run-all.sh` đạt toàn bộ.

## D2. Nginx + ModSecurity

- Image `owasp/modsecurity-crs:nginx-alpine` ghim theo digest (nginx 1.30.6, libmodsecurity 3.0.17, CRS 4.30.0).
- Bỏ qua entrypoint sinh cấu hình từ biến môi trường của image; nhóm tự quản lý `nginx/nginx.conf` và `nginx/modsecurity/*`, để cấu hình nằm trọn trong Git và review được.
- Image chạy nginx bằng user không đặc quyền: nghe 8080/8443 trong container, compose map ra 80/443; `cap_drop: ALL`, `no-new-privileges`.
- WAF chặn: Nginx trả `403` JSON kèm `X-Blocked-By: waf`. Backend không bao giờ đặt header này, nên phân biệt được 403 của WAF với 403 phân quyền của backend.

## D3. Cụm `/api/v1/vuln` đi qua WAF trong lab cô lập

- Ba service lab (`sqli-lab-api`, `sqli-lab-auth-db`, `sqli-lab-db`) nằm trong compose gốc dưới `profiles: [lab]`, chỉ nối `lab_net`.
- Nginx định tuyến `/api/v1/vuln/` (đúng đường dẫn đề cương) và `/lab/...` tới lab API, nên mọi payload tấn công lab đều đi qua WAF.
- Lab có DB định danh, tài khoản DB và JWT secret riêng; token stack chính dùng ở lab bị `401` và ngược lại. Lỗ hổng cố ý không chạm được dữ liệu nghiệp vụ.

## D4. Phạm vi cặp vuln/secure

| Lỗ hổng (đề cương mục 6) | Bản lỗi (lab) | Bản vá (stack chính) |
|---|---|---|
| SQL Injection (nối chuỗi) | `POST /api/v1/vuln/records/search` | `POST /api/v1/secure/records/search` (JPA tham số hóa) |
| Đọc bài nháp của người khác qua ID | `GET /api/v1/vuln/posts/{id}` | `GET /api/v1/posts/{id}` → `403` |
| Lộ email tác giả | `GET /api/v1/vuln/posts/{id}` trả `author.email` | Mọi response bài viết/bình luận chỉ có `id, username, role` |
| Thiếu kiểm tra quyền sở hữu (IDOR) | `PUT/DELETE /api/v1/vuln/posts/{id}` | `PUT/DELETE /api/v1/posts/{id}` → `403` |
| Chưa đăng nhập trả 403 | — | `401` cho route cần xác thực |

## D5. Header, IP thật và log

- Nginx ghi đè `X-Forwarded-For`, `X-Real-IP` bằng `$remote_addr`.
- Backend (profile `integration`) bật `forward-headers-strategy: native` nhưng chỉ tin proxy có IP khớp `TRUSTED_PROXY_REGEX` (IP cố định của `nginx-waf`). Kết nối từ nơi khác, kể cả header giả, vẫn ghi IP của socket.
- Nginx sinh `X-Request-ID` (`$request_id`), đồng thời đặt làm transaction ID của ModSecurity (`modsecurity_transaction_id`). Một mã đối chiếu được giữa log Nginx (`rid=`), audit log WAF (`unique_id`) và log backend (`reqId=`).
- Audit log WAF (JSON) chỉ ghi phần A, H, K, Z: không có header và body request, nên không lộ JWT, mật khẩu.

## D6. WAF: chế độ, ngưỡng, luật tùy chỉnh

- `WAF_MODE=On` mặc định; `DetectionOnly` dùng cho Demo 3 và để dò false positive.
- Paranoia Level 1, ngưỡng anomaly 5 (một luật CRITICAL là chặn). Cho phép thêm `PUT`, `DELETE`.
- JSON Body Inspection: luật 200001 chuyển body `application/json` sang bộ phân tích JSON; mỗi trường thành `ARGS:json.<tên>`. Body JSON hỏng bị chặn `400` (luật 200002).
- Luật tùy chỉnh (`nginx/modsecurity/custom-rules/nhom9-custom.conf`):
  - `100001`: bỏ `password`, `refreshToken` khỏi phạm vi quét CRS ở endpoint xác thực (tránh chặn nhầm mật khẩu có ký tự đặc biệt).
  - `100100`: vá ảo cho `/api/v1/vuln/records/search`, `keyword` chỉ được chứa chữ, số, khoảng trắng và `. , _ -`.
  - `100200`: `username` ở đăng nhập/đăng ký chỉ gồm `A-Z a-z 0-9 _ . @ -`.

## D7. Rate limiting

- Đăng nhập (chính và lab dùng chung vùng): 5 request/phút mỗi IP, burst 5.
- API chung: 5 request/giây, burst 10. Postman Runner và Burp Intruder nên đặt delay khoảng 300 ms.

## D8. Load balancing và failover

- Round-Robin, passive health check `max_fails=1 fail_timeout=15s`, `proxy_connect_timeout 1s`, `proxy_next_upstream error timeout http_502 http_503 http_504`.
- `resolver 127.0.0.11 valid=5s` + `resolve`: Nginx khởi động/restart được khi một node đang tắt và tự nhận node khi nó bật lại với IP mới.

## D9. Chứng chỉ

- Mỗi máy tự sinh bằng `sh nginx/certs/generate-cert.sh` (SAN `DNS:localhost, IP:127.0.0.1`, 365 ngày). Khóa không commit.

## D10. Khởi tạo CSDL

- `database/init/` mount vào `/docker-entrypoint-initdb.d/` của cả DB chính và DB định danh lab: `01-schema.sql`, `02-least-privilege.sql`, `03-seed-data.sql`.
- Chỉ chạy khi volume trống; sửa SQL xong phải `docker compose --profile lab down -v`.
- `.gitattributes` ép LF cho `*.sql`, `*.sh`, `*.conf`, `*.yml` (psql đọc sai meta-command khi dòng kết thúc bằng CRLF).
- Backend kết nối bằng `app_user`: không superuser, không quyền CREATE trên schema.
