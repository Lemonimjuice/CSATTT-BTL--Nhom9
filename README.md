# Cơ sở An toàn Thông tin – BTL Nhóm 9
## Cấu trúc thư mục và người phụ trách

```
CSATTT-BTL--Nhom9/
├── README.md                          # TV1 (dựng khung, cập nhật khi có thay đổi chung; BỔ SUNG: lệnh sinh chứng chỉ, lưu ý "sửa SQL xong phải chạy docker compose down -v", ghi nguồn mã gốc DevFinesse)
├── .gitignore                         # TV1 (BỔ SUNG: .env, logs/, nginx/certs/*.key, nginx/certs/*.crt)
├── .gitattributes                     # TV1 (BỔ SUNG: *.sh text eol=lf, *.sql text eol=lf)
├── .env.example                       # TV1 (mẫu biến môi trường, không chứa mật khẩu thật)
├── docker-compose.yml                 # TV1
├── docs/
│   ├── decisions.md                   # Cả nhóm đề xuất, TV1 chốt (quy ước kỹ thuật chung)
│   ├── test-evidence/                 # TV4 (chỉ vài ảnh quan trọng, bản gốc để trên Drive)
│   └── contract/                      # TV3 chủ trì, cả nhóm đọc
│       ├── api-endpoints.md           # TV3 (danh sách endpoint)
│       ├── db-schema.md               # TV3 (bảng, cột, kiểu dữ liệu), TV4 đối chiếu
│       └── ports-and-env.md           # TV1 (cổng, tên service, biến môi trường; TV2, TV3 gửi biến cần thêm qua file này)
├── nginx/
│   ├── nginx.conf                     # TV1 (upstream, SSL, Rate Limiting; BỔ SUNG: 1 dòng include modsecurity/modsec-nginx.conf)
│   ├── certs/                         # TV1 (chứng chỉ tự sinh, không commit khóa)
│   │   └── generate-cert.sh           # TV1 (MỚI: script openssl tự sinh chứng chỉ)
│   └── modsecurity/                   # TV2
│       ├── modsec-nginx.conf          # TV2 (MỚI: các dòng modsecurity on; modsecurity_rules_file ...)
│       ├── modsecurity.conf           # TV2 (sửa từ file mặc định của image, không viết lại từ đầu)
│       └── custom-rules/              # TV2 (luật tùy chỉnh)
├── backend/                           # TV3 (mã nguồn Spring Boot Blog API)
│   ├── .dockerignore                  # TV3 (MỚI: lấy từ repo gốc)
│   ├── Dockerfile                     # TV3
│   ├── pom.xml                        # TV3
│   └── src/                           # TV3
├── database/
│   └── init/                          # Mount vào /docker-entrypoint-initdb.d/ của PostgreSQL
│       ├── 01-schema.sql              # TV3 (tạo bảng, khớp chính xác entity vì ddl-auto=validate), TV4 đối chiếu
│       ├── 02-least-privilege.sql     # TV3 (tài khoản app_user, quyền tối thiểu)
│       └── 03-seed-data.sql           # TV4 (dữ liệu mẫu: Admin, User A, User B; mật khẩu dạng băm BCrypt)
└── tests/                             # TV4
    ├── postman/                       # TV4 (Postman Collection)
    └── burp/                          # TV4 (mẫu request tấn công)
```


Quy tắc: mỗi file chỉ một người sửa. Muốn sửa file của người khác, báo người đó trước.
