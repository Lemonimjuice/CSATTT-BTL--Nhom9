# C-s-an-to-n-th-ng-tin-BTL--Nh-m-9
## Cấu trúc thư mục và người phụ trách

```
CSATTT-BTL--Nhom9/
├── README.md                          # TV1 (dựng khung, cập nhật khi có thay đổi chung)
├── .gitignore                         # TV1
├── .gitattributes                     # TV1
├── .env.example                       # TV1 (mẫu biến môi trường, không chứa mật khẩu thật)
├── docker-compose.yml                 # TV1
├── docs/
│   ├── decisions.md                   # Cả nhóm (quy ước kỹ thuật chung)
│   ├── test-evidence/                 # TV4 (chỉ vài ảnh quan trọng, bản gốc để trên Drive)
│   └── contract/                      # TV3 chủ trì, cả nhóm đọc
│       ├── api-endpoints.md           # TV3 (danh sách endpoint)
│       ├── db-schema.md               # TV3 (bảng, cột, kiểu dữ liệu), TV4 đối chiếu
│       └── ports-and-env.md           # TV1 (cổng, tên service, biến môi trường)
├── nginx/
│   ├── nginx.conf                     # TV1 (upstream, SSL, Rate Limiting)
│   ├── certs/                         # TV1 (chứng chỉ tự sinh, không commit khóa)
│   └── modsecurity/                   # TV2
│       ├── modsecurity.conf           # TV2
│       └── custom-rules/              # TV2 (luật tùy chỉnh)
├── backend/                           # TV3 (mã nguồn Spring Boot Blog API)
│   ├── Dockerfile                     # TV3
│   ├── pom.xml                        # TV3
│   └── src/                           # TV3
├── database/
│   └── init/                          # Mount vào /docker-entrypoint-initdb.d/ của PostgreSQL
│       ├── 01-schema.sql              # TV3 (tạo bảng), TV4 đối chiếu
│       ├── 02-least-privilege.sql     # TV3 (tài khoản app_user, quyền tối thiểu)
│       └── 03-seed-data.sql           # TV4 (dữ liệu mẫu: Admin, User A, User B)
└── tests/                             # TV4
    ├── postman/                       # TV4 (Postman Collection)
    └── burp/                          # TV4 (mẫu request tấn công)
```

Quy tắc: mỗi file chỉ một người sửa. Muốn sửa file của người khác, báo người đó trước.
    └── burp/                          # TV4 (mẫu request tấn công)

Quy tắc: mỗi file chỉ một người sửa. Muốn sửa file của người khác, báo người đó trước.
