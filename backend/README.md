# TV3 backend — bàn giao V2 (27/10/2026)

> **Ghi chú tích hợp nhóm (27/10/2026), đọc trước:** đây là tài liệu lịch sử của TV3, viết khi cụm `/vuln` còn chạy trong lab riêng. Thiết kế nhóm hiện tại khác ở 4 điểm: (1) cụm `/vuln` bật trên 2 node chính (`SQLI_DEMO_ENABLED=true`), phần SQLi chỉ truy vấn database `sqli_lab` riêng bằng tài khoản chỉ-đọc; (2) không còn lab, identity DB hay JWT riêng, `/vuln` và `/secure` dùng chung token; (3) profile `integration` chỉ tin `X-Forwarded-For` từ IP của `nginx-waf`, nên audit ghi IP client thật; (4) chưa đăng nhập mà đọc bài riêng tư trả `401`. Nginx/WAF đã tích hợp và kiểm chứng. Chi tiết: [docs/decisions.md](../docs/decisions.md).

Tài liệu hiện hành: [hợp đồng tích hợp V2](../docs/contract/tv3-v2-handover.md). Phạm vi sửa là backend và hợp đồng TV3; root Compose/Nginx/WAF do TV1/TV2 quản lý.

## Backend chính

Java 21, Spring Boot 3.2.5, PostgreSQL 16. Build context là `backend/`. Hai node phải dùng cùng image ID, cùng DB và cùng JWT secret Base64 tối thiểu 32 byte ngẫu nhiên. Container nghe cổng 8080; health public `GET /actuator/health`.

Cấu hình mặc định và profile `integration` dùng `ddl-auto: validate`, `show-sql: false`. Dùng role ứng dụng theo `database/init/02-least-privilege.sql`, không dùng provisioning owner. Khởi tạo schema trước khi chạy. Profile `dev` khôi phục auto-DDL `update`/show SQL của workflow phát triển cũ, chỉ opt-in local. Maven tests tự override H2/create-drop nên không phụ thuộc auto-DDL mặc định. Không có `application-prod.yml`; `prod` chỉ có nhánh logging trong `logback-spring.xml`, không bảo đảm validate hay least privilege.

TV1 phải thay hai HTTP Echo bằng image backend, đặt `DB_HOST=database` theo service thật của root Compose, `DB_PORT=5432`, `DB_NAME`, `DB_USERNAME`, `DB_PASSWORD`, `JWT_SECRET`, `SPRING_PROFILES_ACTIVE=integration`, `SQLI_DEMO_ENABLED=false`. Không dùng tên `postgres` của standalone cũ. Chỉ provision hai SQL init trên DB mới, không chạy trên volume nghiệp vụ hiện hữu.

## Lab SQLi

`backend/docker-compose.sqli-lab.yml` là Compose **độc lập**, không ghép root/standalone Compose. Ba service: API, PostgreSQL identity tạm và PostgreSQL fixture. API không nhận credentials DB nghiệp vụ, chỉ nối một network `internal`; hai DB không publish cổng và dùng tmpfs. Auth/JPA dùng schema TV3 ở DB identity tạm với role least privilege; vulnerable JDBC dùng reader riêng chỉ SELECT ba fixture `LAB-ONLY`.

Để chạy HTTP E2E, runner merge thêm `docker-compose.sqli-lab.test.yml`: bỏ publish trực tiếp từ API, thêm gateway HTTP tạm nối internal và edge riêng, chỉ gateway publish loopback ngẫu nhiên. API/DB không vào edge. Base lab Compose không bị thay đổi; không dựa vào port 8081 của base để tái hiện E2E trên Engine chỉ hỗ trợ publish khi có mạng không internal. Gateway test không có ModSecurity/CRS, không chặn SQLi và không thay gateway production của TV1/TV2. Xem [SQLI_TEST_GATEWAY.md](docs/SQLI_TEST_GATEWAY.md).

JWT lab dùng `SQLI_LAB_JWT_SECRET` độc lập. Tài khoản/token nghiệp vụ không dùng cho lab. Đăng ký/login lại ở lab; chỉ tạo dữ liệu giả. Reader/startup checks, timeout và cấm stacked statements vẫn giữ. Tham số của secure search vẫn bind; không bật flag/profile lab trên backend chính.

Mẫu biến lab trong `.env.sqli-lab.example`; không copy credentials từ `.env` standalone. Runner tự sinh secret riêng, không cần điền file credentials. Runtime network/datasource/JWT separation và quyền PostgreSQL đã được kiểm chứng trong lượt E2E cuối. Network nội bộ không phải sandbox chống Docker administrator/host compromise.

## Kiểm thử

`Test-HttpResponse.ps1`: regression mock string/byte[] cho health, response và JSON; không Docker.
`Test-V2Contract.ps1`: Compose schema và effective config, không cần Engine; chỉ dùng template placeholders, không in config/secret.
`Test-V2Host.ps1`: PowerShell 7 + Docker Desktop Linux Engine. Tự sinh project/image/container names và secrets tạm, build code hiện tại, chạy Maven có PostgreSQL lab opt-in, HTTP secure/lab E2E, JWT/Record dùng chéo node, ownership 403, stop node1 rồi đọc node2. Chỉ cleanup tài nguyên thử nghiệm do chính script tạo, không persistent volume. Host cần Internet ở lần build đầu. Script không chứng minh Nginx LB/failover hay ModSecurity/CRS.

Baseline `101d4c6` sau sửa Comment/MDC đạt 92 Maven, 30 HTTP và 12 two-node PASS; xem [SECURITY_REGRESSIONS.md](docs/SECURITY_REGRESSIONS.md). Lượt hardening cuối ngày 27/10/2026 trên Engine 29.9.2 / Compose v5.6.1 đạt **Maven 152/152**, **HTTP secure/lab 42/42**, **two-node HTTP 12/12** PASS, exit code 0; 0 failures/errors/skips trong Maven. Isolation, loopback binding và cleanup PASS. Chi tiết P1/P2, 60 regression mới và thay đổi contract cho TV1/TV4: [FEATURE_FREEZE.md](docs/FEATURE_FREEZE.md). Nginx LB/failover qua gateway nhóm và ModSecurity/CRS vẫn **NOT RUN**.

Từ root checkout, với PowerShell 7 và Docker Desktop Linux Engine hoạt động:

```powershell
pwsh -NoProfile -File ./backend/scripts/Test-V2Host.ps1
```
