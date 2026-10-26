# Cổng, service và biến môi trường

Nguồn sự thật cho `docker-compose.yml` ở thư mục gốc.

## Service và mạng

| Service | Image | Mạng (IP cố định) | Cổng ra host | Ghi chú |
|---|---|---|---|---|
| `nginx-waf` | `owasp/modsecurity-crs:nginx-alpine@sha256:873ce68a…` (nginx 1.30.6, ModSecurity 3.0.17, CRS 4.30.0) | `dmz_net`; `internal_net` (10.209.10.10); `lab_net` (10.209.20.10) | `80`→8080 (redirect), `443`→8443 | Điểm vào duy nhất; nginx chạy uid 101, `cap_drop: ALL` |
| `backend-node-1`, `backend-node-2` | `nhom9/blog-api:local` (build `./backend`) | `internal_net` | không | Cổng nội bộ `8080` |
| `database` | `postgres:16-alpine` | `internal_net` | không | Volume `postgres_data` |
| `sqli-lab-api` | `nhom9/blog-api:local` | `lab_net` | không | Profile `lab`; profile Spring `integration,sqli-lab` |
| `sqli-lab-auth-db` | `postgres:16-alpine` | `lab_net` | không | Profile `lab`; DB định danh lab (tmpfs) |
| `sqli-lab-db` | `postgres:16-alpine` | `lab_net` | không | Profile `lab`; 3 dòng fixture, reader chỉ SELECT (tmpfs) |

`internal_net` (10.209.10.0/24) và `lab_net` (10.209.20.0/24) đều `internal: true`: không ra Internet, không publish cổng. Hai mạng không có container chung ngoài `nginx-waf`, nên lab không thấy DB nghiệp vụ.

Tên container do Compose đặt (`csattt-btl--nhom9-backend-node-1-1`). Thao tác demo dùng tên service: `docker compose stop backend-node-1`.

## Biến trong `.env` (sinh bằng `sh scripts/init-env.sh`, mẫu: `.env.example`)

| Biến | Dùng bởi | Yêu cầu |
|---|---|---|
| `DB_ADMIN_PASSWORD` | `database` (`postgres_admin`) | Ngẫu nhiên; chỉ dùng cho khởi tạo |
| `APP_DB_USERNAME` | `database` (script 02), 2 node (`DB_USERNAME`) | Mặc định `app_user` |
| `APP_DB_PASSWORD` | `database` (script 02), 2 node (`DB_PASSWORD`) | Ngẫu nhiên, tối thiểu 24 ký tự |
| `JWT_SECRET` | 2 node | Base64 của >= 32 byte; backend từ chối khởi động nếu sai |
| `WAF_MODE` | `nginx-waf` | `On` (mặc định) hoặc `DetectionOnly` |
| `SQLI_LAB_AUTH_ADMIN_PASSWORD`, `SQLI_LAB_AUTH_APP_PASSWORD` | `sqli-lab-auth-db`, `sqli-lab-api` | Ngẫu nhiên, app >= 24 ký tự |
| `SQLI_LAB_ADMIN_PASSWORD`, `SQLI_LAB_READER_PASSWORD` | `sqli-lab-db`, `sqli-lab-api` | Ngẫu nhiên |
| `SQLI_LAB_JWT_SECRET` | `sqli-lab-api` | Base64 >= 32 byte, khác `JWT_SECRET` |

Compose kiểm tra đủ biến lab ngay cả khi không bật profile `lab`, nên `.env` luôn phải có đủ 10 biến.

## Biến cố định trong compose

| Biến | Giá trị | Lý do |
|---|---|---|
| `DB_HOST` / `DB_PORT` / `DB_NAME` | `database` / `5432` / `blogdb` | Service thật của compose |
| `SPRING_PROFILES_ACTIVE` | `integration` (lab: `integration,sqli-lab`) | `ddl-auto=validate`, tin proxy theo `TRUSTED_PROXY_REGEX` |
| `SQLI_DEMO_ENABLED` | `false` (lab: `true`) | Cụm `/api/v1/vuln` chỉ tồn tại trong lab |
| `TRUSTED_PROXY_REGEX` | `10\.209\.10\.10` (lab: `10\.209\.20\.10`) | Backend chỉ nhận IP client qua `X-Forwarded-For` khi kết nối đến từ đúng IP của `nginx-waf` |

## Header Nginx gửi xuống backend

| Header | Giá trị | Ghi chú |
|---|---|---|
| `X-Forwarded-For`, `X-Real-IP` | `$remote_addr` | Ghi đè, không nối thêm giá trị client gửi |
| `X-Forwarded-Proto` | `https` | |
| `X-Request-ID` | `$request_id` (32 hex) | Cũng là `unique_id` trong audit log WAF; client không tự đặt được |

Header Nginx trả về client: `X-Request-ID`, `X-Upstream` (chỉ cho demo), `X-Content-Type-Options`, `X-Frame-Options`; khi WAF chặn có thêm `X-Blocked-By: waf`.

## Đường dẫn Nginx

| Location | Rate limit | Đích |
|---|---|---|
| `= /api/v1/auth/login` | 5 r/phút mỗi IP, burst 5 | `backend_cluster` |
| `= /actuator/health` | 5 r/giây, burst 10 | `backend_cluster` |
| `/actuator/` (còn lại) | — | `404` tại Nginx |
| `/` | 5 r/giây, burst 10 | `backend_cluster` |
| `/api/v1/vuln/` | 5 r/giây, burst 10 | `lab_api` (giữ nguyên đường dẫn) |
| `= /lab/api/v1/auth/login` | 5 r/phút, burst 5 (chung vùng với đăng nhập chính) | `lab_api` `/api/v1/auth/login` |
| `/lab/...` | 5 r/giây, burst 10 | `lab_api`, bỏ tiền tố `/lab` |

Lab chưa bật hoặc không còn node nào phản hồi: Nginx trả `503` JSON.
