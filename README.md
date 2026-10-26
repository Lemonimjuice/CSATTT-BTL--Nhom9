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

## Cấu trúc thư mục

```
CSATTT-BTL--Nhom9/
├── docker-compose.yml          # 4 container chính + 3 container lab (profile lab), 3 mạng
├── .env.example                # mẫu biến môi trường (giá trị thật nằm trong .env, không commit)
├── scripts/
│   ├── init-env.sh             # sinh .env ngẫu nhiên
│   └── waf-audit.sh            # xem/xuất audit log ModSecurity
├── nginx/
│   ├── nginx.conf              # upstream, SSL, rate limit, header, định tuyến lab, phản hồi WAF
│   ├── certs/generate-cert.sh  # chứng chỉ tự ký (khóa không commit)
│   └── modsecurity/
│       ├── modsec-nginx.conf   # bật ModSecurity, transaction ID = X-Request-ID
│       ├── main.conf           # thứ tự nạp luật
│       ├── modsecurity.conf    # engine, JSON body processor, audit log
│       ├── crs-tuning.conf     # paranoia level, ngưỡng, method, content type
│       ├── mode/               # On.conf, DetectionOnly.conf (chọn bằng WAF_MODE)
│       └── custom-rules/       # luật tùy chỉnh 100001, 100100, 100200
├── backend/                    # Spring Boot 3.2.5 / Java 21 (Controller – Service – Repository)
├── database/init/              # 01 schema, 02 quyền tối thiểu, 03 dữ liệu mẫu
├── tests/
│   ├── demo/                   # script tự động cho 4 demo
│   ├── postman/                # collection + environment
│   └── burp/                   # request thô cho Repeater/Intruder
└── docs/
    ├── decisions.md            # quy ước kỹ thuật đã chốt
    ├── contract/               # API, schema, cổng và biến môi trường
    └── test-evidence/          # hướng dẫn và nơi lưu minh chứng
```

Quy ước nhánh, header, WAF, rate limit: [docs/decisions.md](docs/decisions.md). Cổng, service, biến môi trường: [docs/contract/ports-and-env.md](docs/contract/ports-and-env.md). API: [docs/contract/api-endpoints.md](docs/contract/api-endpoints.md).

## Nguồn mã

Backend dựa trên [Spring-Boot-Blog-API](https://github.com/DevFinesse/Spring-Boot-Blog-API) của tác giả DevFinesse. Kho gốc không kèm giấy phép; nhóm chỉ dùng cho mục đích học tập và ghi rõ nguồn.
