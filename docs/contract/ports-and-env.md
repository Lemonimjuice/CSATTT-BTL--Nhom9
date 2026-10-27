# Cổng, service và biến môi trường

Nguồn sự thật cho `docker-compose.yml` ở thư mục gốc.

## Service và mạng (đúng 4 container, 2 mạng)

| Service (container_name) | Image | Mạng (IP cố định) | Cổng ra host | Ghi chú |
|---|---|---|---|---|
| `nginx-waf` | `owasp/modsecurity-crs:4.30.0-nginx-alpine-202610180210@sha256:873ce68a…` (CRS 4.30.0, ModSecurity 3.0.17, Nginx 1.30.6, Alpine 3.24.2) | `dmz_net`; `internal_net` (10.209.10.10) | chỉ `443`→8443 (cổng 8080 chỉ dùng nội bộ cho healthcheck) | Điểm vào duy nhất; nginx chạy uid 101, `cap_drop: ALL` |
| `backend-node-1`, `backend-node-2` | `nhom9/blog-api:local` (build `./backend`) | `internal_net` | không | Cổng nội bộ `8080`; chạy cả `/secure` và `/vuln` |
| `database` | `postgres:16-alpine` | `internal_net` | không | Volume `postgres_data`; chứa `blogdb` và `sqli_lab` |

`internal_net` (10.209.10.0/24) `internal: true`: không ra Internet, không publish cổng. Chỉ `nginx-waf` nối thêm `dmz_net`.

Lệnh demo dùng đúng tên service/container: `docker compose stop backend-node-1`.

## Biến trong `.env` (sinh bằng `sh scripts/init-env.sh`, mẫu `.env.example`)

| Biến | Dùng bởi | Yêu cầu |
|---|---|---|
| `DB_ADMIN_PASSWORD` | `database` (`postgres_admin`) | Ngẫu nhiên; chỉ dùng cho khởi tạo |
| `APP_DB_USERNAME` | `database` (script 02), 2 node (`DB_USERNAME`) | Mặc định `app_user` |
| `APP_DB_PASSWORD` | `database` (script 02), 2 node (`DB_PASSWORD`) | Ngẫu nhiên, tối thiểu 24 ký tự |
| `JWT_SECRET` | 2 node | Base64 của >= 32 byte; backend từ chối khởi động nếu sai |
| `WAF_MODE` | `nginx-waf` | `On` (mặc định) hoặc `DetectionOnly` |
| `SQLI_LAB_READER_PASSWORD` | `database` (script 04), 2 node (reader của sqli_lab) | Ngẫu nhiên |

## Biến cố định trong compose

| Biến | Giá trị | Lý do |
|---|---|---|
| `DB_HOST` / `DB_PORT` / `DB_NAME` | `database` / `5432` / `blogdb` | Service thật của compose |
| `SPRING_PROFILES_ACTIVE` | `integration,sqli-lab` | validate; bật cụm `/vuln` để đối chứng |
| `SQLI_DEMO_ENABLED` | `true` | Cụm `/api/v1/vuln` hoạt động trên 2 node |
| `SQLI_DEMO_DB_URL` | `jdbc:postgresql://database:5432/sqli_lab` | Database riêng, reader chỉ đọc |
| `SQLI_DEMO_DB_USERNAME` | `sqli_demo_reader` | Tài khoản chỉ SELECT fixture |
| `TRUSTED_PROXY_REGEX` | `10\.209\.10\.10` | Backend chỉ nhận IP client qua `X-Forwarded-For` khi kết nối đến từ IP của `nginx-waf` |

## Header Nginx gửi xuống backend

| Header | Giá trị | Ghi chú |
|---|---|---|
| `X-Forwarded-For`, `X-Real-IP` | `$remote_addr` | Ghi đè, không nối thêm giá trị client gửi |
| `X-Forwarded-Proto` | `https` | |
| `X-Request-ID` | `$request_id` (32 hex) | Cũng là `unique_id` trong `modsec_audit.log`; client không tự đặt được |

Header trả về client: `X-Request-ID`, `X-Upstream` (chỉ cho demo), `X-Content-Type-Options`, `X-Frame-Options`; khi WAF chặn có thêm `X-Blocked-By: waf`.

## Đường dẫn Nginx

| Location | Rate limit | Đích |
|---|---|---|
| `= /api/v1/auth/login` | 5 r/phút mỗi IP, burst 5 | `backend_cluster` |
| `= /actuator/health` | 5 r/giây, burst 10 | `backend_cluster` |
| `/actuator/` (còn lại) | — | `404` tại Nginx |
| `/swagger-ui*`, `/v3/api-docs*` | — | `404` tại Nginx (tài liệu API không công khai) |
| `/` (gồm `/api/v1/secure` và `/api/v1/vuln`) | 5 r/giây, burst 10 | `backend_cluster` |

Không còn node nào phản hồi: Nginx trả `503` JSON.

## Thư mục log trên host (mount từ container)

| Đường dẫn | Nguồn |
|---|---|
| `logs/nginx/access.log` | Nginx access log |
| `logs/waf/modsec_audit.log` | ModSecurity audit (JSON) |
| `logs/backend-node-1/audit.log`, `logs/backend-node-2/audit.log` | Log ứng dụng mỗi node |

`logs/` nằm trong `.gitignore`.
