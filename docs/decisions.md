# Quy ước kỹ thuật chung

Cả nhóm đề xuất, TV1 chốt. Mỗi mục ghi trạng thái: **Đã chốt** hoặc **Đề xuất** (chờ nhóm đồng ý).

## D1. Nhánh làm việc — Đã chốt (27/10/2026)

- `integration/v2` là nhánh tích hợp. Mỗi thành viên làm trên nhánh riêng tách từ đó (`feat/tv1-infra`, `feat/tv2-waf`, ...) rồi mở PR vào `integration/v2`.
- Chỉ merge `integration/v2` vào `main` khi cả 4 demo đã chạy được qua Nginx.
- Mỗi file một người sửa (README). Cần sửa file của người khác thì báo trước.

## D2. Ghép cấu hình Nginx với ModSecurity — Đã chốt

- TV1 giữ `nginx/nginx.conf` (mount đè file của image). TV2 không viết lại file này mà chỉ:
  - bỏ comment dòng `load_module` ở đầu file (đường dẫn module theo image TV2 chọn);
  - bỏ comment dòng `include /etc/nginx/modsecurity/modsec-nginx.conf;` trong khối `server` HTTPS;
  - thêm volume `./nginx/modsecurity:/etc/nginx/modsecurity:ro` cho `nginx-waf`.
- Image TV2 chọn phải có nginx >= 1.27.3 (cấu hình dùng `resolve` trong `upstream`). Ghi rõ tag cụ thể, không dùng `latest`.
- Khi WAF chặn: trả `403` kèm header `X-Blocked-By: waf` (theo `backend/docs/WAF_INTEGRATION.md`).

## D3. Đưa cụm `/api/v1/vuln` đi qua WAF — Đề xuất

Hiện lab SQLi của TV3 là compose độc lập trong `backend/`, không đi qua Nginx, nên chưa chạy được Demo 2.

Đề xuất (giai đoạn 4):
- Thêm 3 service lab (`sqli-lab-api`, `sqli-lab-auth-db`, `sqli-lab-db`) vào compose gốc dưới `profiles: [lab]`, dùng mạng riêng `lab_net` (`internal: true`).
- `nginx-waf` nối thêm `lab_net`, thêm `location /api/v1/vuln/` trỏ tới `sqli-lab-api:8080`.
- Lab **không** nối vào `internal_net`, không dùng chung DB, tài khoản hay JWT secret với stack chính.

## D4. Phạm vi cụm `/vuln` — Chờ nhóm quyết

Đề cương (mục 5, TV3.3) nói cụm `/vuln` gồm cả lỗi đọc bài nháp, lộ email, thiếu kiểm tra quyền. Code hiện chỉ có SQLi tìm kiếm Record. Hoặc TV3 bổ sung, hoặc sửa đề cương cho khớp.

## D5. Header và log — Đã chốt

- Nginx là điểm vào duy nhất nên ghi đè `X-Forwarded-For` bằng `$remote_addr` (client không chèn được IP giả).
- Nginx sinh `X-Request-ID` (`$request_id`, 32 ký tự hex) và gửi xuống backend. Backend ghi ID này vào log, nên một request có thể đối chiếu giữa log Nginx, audit log WAF và log backend.
- Log truy cập Nginx ghi `rid=` và `upstream=` để làm minh chứng Demo 1.
- Header `X-Upstream` chỉ dùng cho môi trường demo (lộ IP nội bộ).

## D6. Rate limiting — Đề xuất, chờ TV4 xác nhận

- Đăng nhập: 5 request/phút mỗi IP, burst 3 (đã kiểm: request thứ 5 liên tiếp trả `429`).
- API chung: 5 request/giây, burst 10. Nếu Postman Runner/Burp Intruder bị `429` ở các demo không liên quan brute-force thì tăng ngưỡng hoặc giãn thời gian giữa các request.

## D7. Chứng chỉ — Đã chốt

- Mỗi máy tự sinh bằng `sh nginx/certs/generate-cert.sh`, có SAN `DNS:localhost, IP:127.0.0.1`, hạn 365 ngày.
- `server.key`, `server.crt` không commit (`.gitignore`). Client kiểm thử dùng `--cacert nginx/certs/server.crt` thay vì tắt xác thực.

## D8. Khởi tạo CSDL — Đã chốt

- `database/init/` được mount vào `/docker-entrypoint-initdb.d/`, chạy theo thứ tự tên file: `01-schema.sql`, `02-least-privilege.sql` (TV3), `03-seed-data.sql` (TV4).
- Script chỉ chạy khi volume trống. Sửa SQL xong phải `docker compose down -v`.
- `.gitattributes` ép LF cho `*.sql`, `*.sh`: psql đọc sai meta-command (`\getenv`, `\if`) khi dòng kết thúc bằng CRLF.
- Backend kết nối bằng `app_user` (không superuser, không quyền CREATE trên schema `public`); `postgres_admin` chỉ dùng cho khởi tạo.
