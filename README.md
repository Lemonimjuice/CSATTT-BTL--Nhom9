# Cơ sở An toàn Thông tin – BTL Nhóm 9

Kiến trúc phòng thủ đa lớp (Defense in Depth) tích hợp WAF trên Load Balancer cho ứng dụng Spring Boot phân lớp.

```text
                 Internet / máy kiểm thử
                          │ chỉ mở HTTPS 443
              ┌───────────▼─────────────┐  dmz_net
 Lớp 1        │ nginx-waf               │  SSL Termination, Rate Limiting, Round-Robin + Failover,
 (biên)       │ ModSecurity + OWASP CRS │  JSON Body Inspection, vá ảo, X-Request-ID
              └───────────┬─────────────┘
                          │ internal_net (10.209.10.0/24, không ra Internet)
          ┌───────────────┼───────────────┐
   ┌──────▼──────┐ ┌──────▼──────┐ ┌───────▼────────┐
   │backend-node-1│ │backend-node-2│ │ database       │ PostgreSQL 16
   │  /secure (vá)│ │  /secure (vá)│ │ ├ blogdb       │ nghiệp vụ, tài khoản app_user (quyền tối thiểu)
   │  /vuln (lỗi) │ │  /vuln (lỗi) │ │ └ sqli_lab     │ dữ liệu giả cho SQLi, tài khoản chỉ-đọc
   └─────────────┘ └─────────────┘ └────────────────┘
   2 node dùng chung image, JWT secret và CSDL
```

Đúng **4 container** và **2 phân vùng mạng** như đề cương. Cụm API lỗi `/api/v1/vuln` chạy song song với
cụm vá `/api/v1/secure` ngay trên 2 node backend. Dữ liệu cho phần SQLi nằm ở database `sqli_lab` riêng
trong cùng PostgreSQL, truy cập bằng tài khoản chỉ-đọc; PostgreSQL không cho truy vấn chéo database nên
lỗ hổng cố ý không chạm được bảng của `blogdb`.

## Chạy hệ thống

Yêu cầu: Docker Desktop (Compose v2) và **Git Bash** (cài cùng Git for Windows, có sẵn `openssl` và `sh`).
Mọi lệnh dưới đây chạy **trong Git Bash** (chuột phải thư mục repo > *Open Git Bash here*), từ thư mục gốc
repo; không chạy trong PowerShell hay CMD. macOS/Linux dùng terminal bình thường.

**1. Chuẩn bị môi trường**: tạo thư mục `logs/` và sinh file `.env` với mọi mật khẩu, khóa ngẫu nhiên
(chạy lại nhiều lần cũng an toàn, không ghi đè `.env` đã có):

```bash
sh scripts/init-env.sh
```

**2. Sinh chứng chỉ tự ký** (có SAN cho `localhost` và `127.0.0.1`; khóa không được commit):

```bash
sh nginx/certs/generate-cert.sh
```

**3. Build và chạy** (lần đầu mất vài phút và cần Internet; sau mỗi lần `git pull` luôn kèm `--build`):

```bash
docker compose up -d --build --wait
```

Truy cập qua `https://localhost` (chỉ mở cổng 443, không có `http://`).

**4. Kiểm tra nhanh** toàn hệ thống (Docker, `.env`, chứng chỉ, 4 container, WAF, dữ liệu mẫu), in PASS/WARN/FAIL
kèm cách sửa:

```bash
sh scripts/preflight.sh
```

**5. Chạy toàn bộ demo** (các kiểm tra tự động, in kết quả PASS/FAIL):

```bash
sh tests/demo/run-all.sh
```

**Đưa về trạng thái sạch** (xóa dữ liệu DB và log, dựng lại với dữ liệu mẫu gốc, rồi chạy preflight). Dùng trước
buổi trình bày, sau khi sửa file trong `database/init/`, hoặc khi cập nhật từ bản cũ:

```bash
sh scripts/reset-demo.sh --yes
```

Trước buổi trình bày đọc [docs/demo-checklist.md](docs/demo-checklist.md): việc cần làm, lưu ý khi demo và bảng
xử lý sự cố.

## Tài khoản thử nghiệm

Nạp từ `database/init/03-seed-data.sql`. Chỉ dùng trên máy lab.

| Username | Mật khẩu | Vai trò | Dữ liệu |
|---|---|---|---|
| `admin` | `Admin@Nhom9-2026` | ADMIN | bài 1 |
| `user_a` | `UserA@Nhom9-2026` | USER | bài 2 (công khai), **bài 3 (NHÁP)**, Record 1–2 |
| `user_b` | `UserB@Nhom9-2026` | USER | bài 4, Record 3–4 |

Mọi route dùng chung token lấy ở `/api/v1/auth/login`.

## Bốn demo

| Demo | Script | Nội dung kiểm chứng |
|---|---|---|
| 1. HA & Failover | `tests/demo/demo1-failover.sh` | `docker compose stop backend-node-1`, token cũ vẫn dùng được, Nginx chuyển sang node 2 |
| 2. Vá ảo tại WAF | `tests/demo/demo2-waf-virtual-patch.sh` | SQLi vào `/api/v1/vuln/records/search` bị WAF chặn `403`, audit có rule `100100`, backend không nhận request |
| 3. Defense in Depth | `tests/demo/demo3-defense-in-depth.sh` | WAF chuyển DetectionOnly: bản lỗi lộ 3 dòng, bản vá (Parameterized Query) trả `[]`; UNION sang `blogdb` thất bại |
| 4. Chống IDOR | `tests/demo/demo4-idor.sh` | User B thao tác trên nháp của A tại `/api/v1/secure/posts/{id}`: `403` từ backend (không có `X-Blocked-By`), chưa đăng nhập `401`; bản lỗi `/api/v1/vuln/posts/{id}` cho người chưa đăng nhập đọc nháp (lộ email) và cho B sửa bài |
| Bổ sung | `tests/demo/demo5-ratelimit-audit.sh` | Brute-force đăng nhập bị `429`; IP giả trong `X-Forwarded-For` không vào audit log; 1 request ID xuyên suốt Nginx, WAF, backend; Swagger, actuator và cổng 80 không mở ra ngoài |

Demo 3 đổi chế độ WAF bằng `sh scripts/waf-mode.sh DetectionOnly` và trả lại bằng `sh scripts/waf-mode.sh On`
(script demo tự làm việc này).

Kiểm thử thủ công: Postman trong `tests/postman/` (phủ toàn bộ API), mẫu request Burp trong `tests/burp/`
(hướng dẫn trong [tests/burp/README.md](tests/burp/README.md)).
Thu thập minh chứng: [docs/test-evidence/README.md](docs/test-evidence/README.md).

## Audit log tập trung

Khi chạy, mọi log ghi ra thư mục `logs/` trên máy (đã có trong `.gitignore`):

```
logs/
├── nginx/access.log              # log truy cập Nginx (có rid, upstream)
├── waf/modsec_audit.log          # audit log ModSecurity (JSON, không chứa token/mật khẩu)
├── backend-node-1/audit.log      # log ứng dụng node 1 (reqId, user, ip)
└── backend-node-2/audit.log      # log ứng dụng node 2
```

Một request có thể đối chiếu qua 3 lớp bằng `X-Request-ID` (= `unique_id` trong audit WAF, `reqId=` trong log backend).
Log backend bỏ các dòng healthcheck nội bộ của Docker (mỗi 10 giây) để chỉ còn sự kiện thật. Giờ trong log là UTC
(giờ Việt Nam = UTC+7).

## Cấu trúc thư mục và người phụ trách

```
CSATTT-BTL--Nhom9/
├── README.md                          # TV1 (dựng khung, hướng dẫn chạy, tài khoản thử, nguồn mã DevFinesse)
├── .gitignore                         # TV1 (.env, logs/, target/, *.key, *.crt)
├── .gitattributes                     # TV1 (ép LF cho *.sh, *.sql, *.conf, *.yml; *.http giữ CRLF)
├── .env.example                       # TV1 (mẫu biến môi trường, không chứa mật khẩu thật)
├── docker-compose.yml                 # TV1 (4 container, 2 mạng; TV2/TV3 gửi thay đổi qua ports-and-env.md)
├── scripts/
│   ├── init-env.sh                    # TV1 (tạo thư mục logs/, sinh .env với mật khẩu, khóa ngẫu nhiên)
│   ├── preflight.sh                   # TV1 (kiểm tra nhanh toàn hệ thống trước khi trình bày)
│   ├── reset-demo.sh                  # TV1 (xóa dữ liệu, dựng lại sạch với dữ liệu mẫu gốc)
│   ├── waf-mode.sh                    # TV2 (đổi chế độ WAF On / DetectionOnly)
│   └── waf-audit.sh                   # TV2 (xem modsec_audit.log theo request ID)
├── docs/
│   ├── decisions.md                   # Cả nhóm đề xuất, TV1 chốt (quy ước kỹ thuật chung)
│   ├── demo-checklist.md              # TV4 (checklist trình bày, bảng xử lý sự cố; cả nhóm đọc)
│   ├── test-evidence/                 # TV4 (hướng dẫn chụp minh chứng; bản gốc để trên Drive)
│   └── contract/                      # TV3 chủ trì, cả nhóm đọc
│       ├── api-endpoints.md           # TV3 (danh sách endpoint, cặp /vuln – /secure)
│       ├── db-schema.md               # TV3 (bảng, cột, kiểu dữ liệu), TV4 đối chiếu
│       ├── tv3-v2-handover.md         # TV3 (biên bản bàn giao backend)
│       └── ports-and-env.md           # TV1 (cổng, tên service, biến môi trường)
├── nginx/
│   ├── nginx.conf                     # TV1 (upstream, SSL, Rate Limiting, header; include modsecurity/modsec-nginx.conf)
│   ├── certs/generate-cert.sh         # TV1 (script openssl tự sinh chứng chỉ có SAN; khóa không commit)
│   └── modsecurity/                   # TV2
│       ├── modsec-nginx.conf          # TV2 (modsecurity on; transaction ID = X-Request-ID)
│       ├── main.conf                  # TV2 (thứ tự nạp luật)
│       ├── modsecurity.conf           # TV2 (SecRuleEngine On, JSON body processor, modsec_audit.log)
│       ├── crs-tuning.conf            # TV2 (paranoia level, ngưỡng, method, content type, ngoại lệ)
│       ├── mode/                      # TV2 (On.conf, DetectionOnly.conf, chọn bằng WAF_MODE)
│       └── custom-rules/              # TV2 (đúng 2 luật tùy chỉnh: 100100, 100200)
├── backend/                           # TV3 (Spring Boot 3.2.5 / Java 21; cụm /secure và /vuln trong src/.../controller, demo)
│   ├── Dockerfile, pom.xml, src/      # TV3 (test cặp /secure – /vuln: src/test/.../PostSecureVulnPairIntegrationTest.java)
│   └── (docker-compose.sqli-lab*.yml, scripts/, docs/ của bộ kiểm thử E2E riêng — TV3)
├── database/
│   └── init/                          # Mount vào /docker-entrypoint-initdb.d/ của PostgreSQL
│       ├── 01-schema.sql              # TV3 (tạo bảng, ddl-auto=validate), TV4 đối chiếu
│       ├── 02-least-privilege.sql     # TV3 (tài khoản app_user, quyền tối thiểu)
│       ├── 03-seed-data.sql           # TV4 (dữ liệu mẫu: Admin, User A, User B; mật khẩu băm BCrypt)
│       └── 04-sqli-demo.sh            # TV1 (database sqli_lab + tài khoản chỉ-đọc cho cụm /vuln)
└── tests/                             # TV4
    ├── demo/                          # TV4 tổng hợp (run-all.sh, common.sh); mỗi demo do người phụ trách lớp đó kiểm
    ├── postman/                       # TV4 (Postman Collection phủ toàn bộ API + environment)
    └── burp/                          # TV4 (mẫu request tấn công cho Repeater/Intruder)
```

Quy tắc: mỗi file chỉ một người sửa. Muốn sửa file của người khác, báo người đó trước.
Quy ước kỹ thuật: [docs/decisions.md](docs/decisions.md). Cổng, service, biến: [docs/contract/ports-and-env.md](docs/contract/ports-and-env.md). API: [docs/contract/api-endpoints.md](docs/contract/api-endpoints.md).

## Nguồn mã

Backend dựa trên [Spring-Boot-Blog-API](https://github.com/DevFinesse/Spring-Boot-Blog-API) của tác giả DevFinesse. Kho gốc không kèm giấy phép; nhóm chỉ dùng cho mục đích học tập và ghi rõ nguồn.
