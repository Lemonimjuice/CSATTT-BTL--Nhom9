# Cơ sở An toàn Thông tin – BTL Nhóm 9

Kiến trúc phòng thủ đa lớp (Defense in Depth) tích hợp WAF trên Load Balancer cho ứng dụng Spring Boot phân lớp.

```text
                 Internet / máy kiểm thử
                          │ HTTPS 443 (HTTP 80 chỉ redirect)
              ┌───────────▼────────────┐  dmz_net
 Lớp 1        │ nginx-waf              │  SSL Termination, Rate Limiting, Round-Robin + Failover,
 (biên)       │ ModSecurity + OWASP CRS│  JSON Body Inspection, vá ảo, X-Request-ID
              └──┬──────────────────┬──┘
     internal_net│                  │lab_net (profile lab, tách biệt)
 Lớp 2   ┌───────▼──────┐   ┌───────▼────────┐
 (mã     │ backend-node-1│   │ sqli-lab-api   │  cụm API lỗi /api/v1/vuln (đối chứng)
 nguồn & │ backend-node-2│   │ + 2 DB lab tạm │  DB, tài khoản, JWT secret riêng
 dữ liệu)└───────┬──────┘   └────────────────┘
                 │ app_user (quyền tối thiểu)
         ┌───────▼──────┐
         │ database     │ PostgreSQL 16
         └──────────────┘
```

## Chạy hệ thống

Yêu cầu: Docker Desktop (Compose v2), Git Bash (có sẵn `openssl` và `sh`). Mọi lệnh chạy từ thư mục gốc repo.

**1. Sinh file `.env`** với mọi mật khẩu, khóa ngẫu nhiên (không ghi đè nếu đã có):

```bash
sh scripts/init-env.sh
```

**2. Sinh chứng chỉ tự ký** (có SAN cho `localhost` và `127.0.0.1`; khóa không được commit):

```bash
sh nginx/certs/generate-cert.sh
```

**3. Build và chạy toàn bộ**, kèm lab cô lập cho cụm `/api/v1/vuln` (lần đầu mất vài phút):

```bash
docker compose --profile lab up -d --build --wait
```

Chỉ cần stack chính (WAF + 2 node + DB) thì bỏ `--profile lab`.

**4. Chạy toàn bộ demo** (31 kiểm tra tự động, in kết quả PASS/FAIL):

```bash
sh tests/demo/run-all.sh
```

**Sửa file SQL trong `database/init/` xong phải xóa volume** rồi chạy lại, vì PostgreSQL chỉ chạy script khởi tạo khi volume trống. Lệnh này xóa toàn bộ dữ liệu cũ:

```bash
docker compose --profile lab down -v
```

## Tài khoản thử nghiệm

Nạp từ `database/init/03-seed-data.sql` cho cả DB chính và DB lab. Chỉ dùng trên máy lab.

| Username | Mật khẩu | Vai trò | Dữ liệu |
|---|---|---|---|
| `admin` | `Admin@Nhom9-2026` | ADMIN | bài 1 |
| `user_a` | `UserA@Nhom9-2026` | USER | bài 2 (công khai), **bài 3 (NHÁP)**, Record 1–2 |
| `user_b` | `UserB@Nhom9-2026` | USER | bài 4, Record 3–4 |

Token stack chính lấy ở `/api/v1/auth/login`; token lab lấy ở `/lab/api/v1/auth/login` (hai bên không dùng chéo được).

## Bốn demo

| Demo | Script | Nội dung kiểm chứng |
|---|---|---|
| 1. HA & Failover | `tests/demo/demo1-failover.sh` | Stop `backend-node-1`, token cũ vẫn dùng được, Nginx chuyển sang node 2 |
| 2. Vá ảo tại WAF | `tests/demo/demo2-waf-virtual-patch.sh` | SQLi vào `/api/v1/vuln/records/search` bị WAF chặn `403`, audit có rule `100100`, backend không nhận request |
| 3. Defense in Depth | `tests/demo/demo3-defense-in-depth.sh` | WAF chuyển DetectionOnly: bản lỗi lộ 3 dòng, bản vá (Parameterized Query) trả `[]` |
| 4. Chống IDOR | `tests/demo/demo4-idor.sh` | User B sửa/xóa/đọc nháp của A: `403` từ backend (không có `X-Blocked-By`), chưa đăng nhập `401`; bản lỗi trong lab cho phép |
| Bổ sung | `tests/demo/demo5-ratelimit-audit.sh` | Brute-force đăng nhập bị `429`; IP giả trong `X-Forwarded-For` không vào audit log; 1 request ID xuyên suốt Nginx, WAF, backend |

Kiểm thử thủ công: Postman trong `tests/postman/`, mẫu request Burp trong `tests/burp/` (hướng dẫn trong [tests/burp/README.md](tests/burp/README.md)).
Cách thu thập minh chứng cho báo cáo: [docs/test-evidence/README.md](docs/test-evidence/README.md).

## Cấu trúc thư mục và người phụ trách

```
CSATTT-BTL--Nhom9/
├── README.md                          # TV1 (dựng khung, cập nhật khi có thay đổi chung; lệnh chạy, tài khoản thử nghiệm, nguồn mã DevFinesse)
├── .gitignore                         # TV1 (.env, logs/, target/, *.key, *.crt)
├── .gitattributes                     # TV1 (ép LF cho *.sh, *.sql, *.conf, *.yml; *.http giữ CRLF)
├── .env.example                       # TV1 (mẫu biến môi trường, không chứa mật khẩu thật)
├── docker-compose.yml                 # TV1 (4 container chính + 3 container lab profile `lab`, 3 mạng; TV2/TV3 gửi thay đổi qua ports-and-env.md)
├── scripts/
│   ├── init-env.sh                    # TV1 (sinh .env với mật khẩu, khóa ngẫu nhiên)
│   └── waf-audit.sh                   # TV2 (xem/xuất audit log ModSecurity)
├── docs/
│   ├── decisions.md                   # Cả nhóm đề xuất, TV1 chốt (quy ước kỹ thuật chung)
│   ├── test-evidence/                 # TV4 (hướng dẫn chụp minh chứng; chỉ vài ảnh quan trọng, bản gốc để trên Drive)
│   └── contract/                      # TV3 chủ trì, cả nhóm đọc
│       ├── api-endpoints.md           # TV3 (danh sách endpoint, cặp /vuln – /secure)
│       ├── db-schema.md               # TV3 (bảng, cột, kiểu dữ liệu), TV4 đối chiếu
│       ├── tv3-v2-handover.md         # TV3 (biên bản bàn giao backend)
│       └── ports-and-env.md           # TV1 (cổng, tên service, biến môi trường; TV2, TV3 gửi biến cần thêm qua file này)
├── nginx/
│   ├── nginx.conf                     # TV1 (upstream, SSL, Rate Limiting, header, định tuyến lab; 1 dòng include modsecurity/modsec-nginx.conf)
│   ├── certs/                         # TV1 (chứng chỉ tự sinh, không commit khóa)
│   │   └── generate-cert.sh           # TV1 (script openssl tự sinh chứng chỉ có SAN)
│   └── modsecurity/                   # TV2
│       ├── modsec-nginx.conf          # TV2 (modsecurity on; modsecurity_rules_file; transaction ID = X-Request-ID)
│       ├── main.conf                  # TV2 (thứ tự nạp: engine, chế độ, CRS setup, luật tùy chỉnh, CRS rules)
│       ├── modsecurity.conf           # TV2 (sửa từ file mặc định của image: JSON body processor, audit log)
│       ├── crs-tuning.conf            # TV2 (paranoia level, ngưỡng anomaly, method, content type)
│       ├── mode/                      # TV2 (On.conf, DetectionOnly.conf, chọn bằng WAF_MODE)
│       └── custom-rules/              # TV2 (luật tùy chỉnh 100001, 100100, 100200)
├── backend/                           # TV3 (mã nguồn Spring Boot Blog API, gồm cụm /vuln trong src/.../demo/)
│   ├── .dockerignore                  # TV3 (lấy từ repo gốc)
│   ├── Dockerfile                     # TV3
│   ├── pom.xml                        # TV3
│   ├── src/                           # TV3
│   ├── docker/, docker-compose.sqli-lab*.yml, scripts/, docs/   # TV3 (lab độc lập và bộ kiểm thử E2E riêng của backend)
│   └── README.md                      # TV3
├── database/
│   └── init/                          # Mount vào /docker-entrypoint-initdb.d/ của PostgreSQL (DB chính và DB lab)
│       ├── 01-schema.sql              # TV3 (tạo bảng, khớp chính xác entity vì ddl-auto=validate), TV4 đối chiếu
│       ├── 02-least-privilege.sql     # TV3 (tài khoản app_user, quyền tối thiểu)
│       └── 03-seed-data.sql           # TV4 (dữ liệu mẫu: Admin, User A, User B; mật khẩu dạng băm BCrypt)
└── tests/                             # TV4
    ├── demo/                          # TV4 tổng hợp (run-all.sh, common.sh); từng demo do người phụ trách lớp đó kiểm:
    │   ├── demo1-failover.sh          #   TV1 (HA & Failover)
    │   ├── demo2-waf-virtual-patch.sh #   TV2 (vá ảo tại WAF)
    │   ├── demo3-defense-in-depth.sh  #   TV3 (Parameterized Query khi WAF bị lách)
    │   ├── demo4-idor.sh              #   TV4 (chống IDOR)
    │   └── demo5-ratelimit-audit.sh   #   TV1 + TV3 (rate limit, IP thật, request ID)
    ├── postman/                       # TV4 (Postman Collection + environment)
    └── burp/                          # TV4 (mẫu request tấn công cho Repeater/Intruder)
```

Quy tắc: mỗi file chỉ một người sửa. Muốn sửa file của người khác, báo người đó trước.

Quy ước nhánh, header, WAF, rate limit: [docs/decisions.md](docs/decisions.md). Cổng, service, biến môi trường: [docs/contract/ports-and-env.md](docs/contract/ports-and-env.md). API: [docs/contract/api-endpoints.md](docs/contract/api-endpoints.md).

## Nguồn mã

Backend dựa trên [Spring-Boot-Blog-API](https://github.com/DevFinesse/Spring-Boot-Blog-API) của tác giả DevFinesse. Kho gốc không kèm giấy phép; nhóm chỉ dùng cho mục đích học tập và ghi rõ nguồn.
