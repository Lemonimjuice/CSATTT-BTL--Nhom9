# Cổng, service và biến môi trường (TV1)

Nguồn sự thật cho `docker-compose.yml` ở thư mục gốc. TV2, TV3, TV4 cần thêm biến/cổng thì ghi đề xuất vào cuối file này và báo TV1.

## Service và mạng

| Service | Image | Mạng | Cổng ra host | Ghi chú |
|---|---|---|---|---|
| `nginx-waf` | `nginx:1.28-alpine` (TV2 sẽ đổi sang image ModSecurity + CRS, cần nginx >= 1.27.3) | `dmz_net`, `internal_net` | `80` (chỉ redirect), `443` | Điểm vào duy nhất từ bên ngoài |
| `backend-node-1` | `nhom9/blog-api:local` (build từ `./backend`) | `internal_net` | không | Cổng nội bộ `8080` |
| `backend-node-2` | `nhom9/blog-api:local` (cùng image) | `internal_net` | không | Cổng nội bộ `8080` |
| `database` | `postgres:16-alpine` | `internal_net` | không | Cổng nội bộ `5432`, volume `postgres_data` |

`internal_net` có `internal: true`: không có đường ra Internet. Chỉ `nginx-waf` nối cả hai mạng.

Tên container do Compose tự đặt (`csattt-btl--nhom9-backend-node-1-1`). Thao tác demo dùng tên service: `docker compose stop backend-node-1`.

## Biến trong `.env` (mẫu: `.env.example`)

| Biến | Dùng bởi | Yêu cầu |
|---|---|---|
| `DB_ADMIN_PASSWORD` | `database` (`POSTGRES_PASSWORD` của `postgres_admin`) | Ngẫu nhiên; chỉ dùng cho khởi tạo, backend không dùng |
| `APP_DB_USERNAME` | `database` (script 02 tạo role), 2 node (`DB_USERNAME`) | Mặc định `app_user` |
| `APP_DB_PASSWORD` | `database` (script 02), 2 node (`DB_PASSWORD`) | Ngẫu nhiên, **tối thiểu 24 ký tự** |
| `JWT_SECRET` | 2 node | **Base64** của >= 32 byte ngẫu nhiên, giống nhau trên 2 node |

## Biến cố định trong compose (không đặt trong `.env`)

| Biến | Giá trị | Lý do |
|---|---|---|
| `DB_HOST` / `DB_PORT` / `DB_NAME` | `database` / `5432` / `blogdb` | Theo service thật của compose gốc |
| `SPRING_PROFILES_ACTIVE` | `integration` | `ddl-auto=validate`, `show-sql=false` |
| `SQLI_DEMO_ENABLED` | `false` | Cụm `/api/v1/vuln` không bao giờ bật trên backend chính |
| `POSTGRES_USER` / `POSTGRES_DB` | `postgres_admin` / `blogdb` | Chủ sở hữu schema |

## Header Nginx gửi xuống backend

| Header | Giá trị | Ghi chú |
|---|---|---|
| `X-Forwarded-For`, `X-Real-IP` | `$remote_addr` | Ghi đè, không nối thêm giá trị client gửi lên |
| `X-Forwarded-Proto` | `https` | |
| `X-Request-ID` | `$request_id` (32 ký tự hex) | Giá trị client tự gửi bị thay; Nginx trả lại đúng 1 header này cho client |

## Đường dẫn Nginx

| Location | Rate limit | Đích |
|---|---|---|
| `= /api/v1/auth/login` | 5 r/phút mỗi IP, burst 3 | `backend_cluster` |
| `= /actuator/health` | 5 r/giây, burst 10 | `backend_cluster` |
| `/actuator/` (còn lại) | — | `404` tại Nginx |
| `/` | 5 r/giây, burst 10 | `backend_cluster` |
| `/api/v1/vuln/` | — | Chưa có, xem `docs/decisions.md` (D3) |

## Đề xuất thêm biến/cổng

_(Ghi theo dạng: người đề xuất, biến/cổng, lý do.)_
