# TV3 backend — bàn giao V2 (27/10/2026)

Tài liệu hiện hành: [hợp đồng tích hợp V2](../../docs/contract/tv3-v2-handover.md). Phạm vi sửa là backend và hợp đồng TV3; root Compose/Nginx/WAF do TV1/TV2 quản lý.

## Backend chính

Java 21, Spring Boot 3.2.5, PostgreSQL 16. Build context là `backend/`. Hai node phải dùng cùng image ID, cùng DB và cùng JWT secret Base64 tối thiểu 32 byte ngẫu nhiên. Container nghe cổng 8080; health public `GET /actuator/health`.

Cấu hình mặc định và profile `integration` dùng `ddl-auto: validate`, `show-sql: false`. Dùng role ứng dụng theo `database/init/02-least-privilege.sql`, không dùng provisioning owner. Khởi tạo schema trước khi chạy. Profile `dev` khôi phục auto-DDL `update`/show SQL của workflow phát triển cũ, chỉ opt-in local. Maven tests tự override H2/create-drop nên không phụ thuộc auto-DDL mặc định. Không có `application-prod.yml`; `prod` chỉ có nhánh logging trong `logback-spring.xml`, không bảo đảm validate hay least privilege.

TV1 phải thay hai HTTP Echo bằng image backend, đặt `DB_HOST=database` theo service thật của root Compose, `DB_PORT=5432`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`, `JWT_SECRET`, `SPRING_PROFILES_ACTIVE=integration`, `SQLI_DEMO_ENABLED=false`. Không dùng tên `postgres` của standalone cũ. Chỉ provision hai SQL init trên DB mới, không chạy trên volume nghiệp vụ hiện hữu.

## Lab SQLi

`backend/docker-compose.sqli-lab.yml` hiện là Compose **độc lập**, không ghép root/standalone Compose. Ba service: API, PostgreSQL identity tạm và PostgreSQL fixture. API không nhận credentials DB nghiệp vụ, chỉ nối một network `internal`; API publish loopback, hai DB không publish cổng và dùng tmpfs. Auth/JPA dùng schema TV3 ở DB identity tạm với role least privilege; vulnerable JDBC dùng reader riêng chỉ SELECT ba fixture `LAB-ONLY`. Không thay Auth để bỏ lookup user.

JWT lab dùng `SQLI_LAB_JWT_SECRET` độc lập. Tài khoản/token nghiệp vụ không dùng cho lab. Đăng ký/login lại ở lab; chỉ tạo dữ liệu giả. Reader/startup checks, timeout và cấm stacked statements vẫn giữ. Tham số của secure search vẫn bind; không bật flag/profile lab trên backend chính.

Mẫu biến lab trong `.env.sqli-lab.example`; không copy credentials từ `.env` standalone. Compose path tương đối đã trỏ tới init SQL của repo nhóm. Không tuyên bố runtime cô lập đạt chỉ từ config: cần chạy host runner để kiểm chứng network, datasource, JWT tách biệt và quyền PostgreSQL. Network nội bộ không phải sandbox chống Docker administrator/host compromise.

## Kiểm thử

`Test-HttpResponse.ps1`: regression mock string/byte[] cho health, response và JSON; không Docker.
`Test-V2Contract.ps1`: Compose schema và effective config, không cần Engine; chỉ dùng template placeholders, không in config/secret.
`Test-V2Host.ps1`: PowerShell 7 + Docker Desktop Linux Engine. Tự sinh project/image/container names và secrets tạm, build code hiện tại, chạy Maven có PostgreSQL lab opt-in, HTTP secure/lab E2E, JWT/Record dùng chéo node, ownership 403, stop node1 rồi đọc node2. Chỉ cleanup tài nguyên thử nghiệm do chính script tạo, không persistent volume. Host cần Internet ở lần build đầu. Script không chứng minh Nginx LB/failover hay ModSecurity/CRS.

Lệnh duy nhất để chạy phần Docker còn thiếu nằm trong hợp đồng V2. Các kết quả cũ 27 Maven/26 HTTP/SQL init/Hibernate validate là lịch sử standalone; không phải bằng chứng phiên hiện tại.
