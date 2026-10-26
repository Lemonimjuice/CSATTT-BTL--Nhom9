# Hợp đồng và kiểm toán TV3 V2 — 27/10/2026

## Phạm vi và snapshot

Repo: `D:\ProJect An Toan Thong TIn\Codex\CSATTT-BTL--Nhom9-integration`, branch `feat/tv3-backend`, HEAD `9aa014b`. Đầu phiên chỉ có `backend/scripts/TwoNode-Diagnostic-REUPLOAD.ps1` untracked; giữ nguyên. Không có diff của root `.gitignore`/`README.md`/application.yml ở đầu phiên như snapshot cũ mô tả. Không commit/push; không reset/clean/rebase/merge/pull. Standalone chỉ đọc để so sánh script fixed; không đọc các .env thật.

## Ma trận đối chiếu source và bằng chứng

IMPLEMENTED = có trong source/config; TESTED = có kiểm tra chạy trong phiên; UNVERIFIED = runtime còn thiếu; MISSING = chưa có thành phần tương ứng. TESTED phải đọc kèm môi trường, không suy ra Docker E2E từ H2.

| Yêu cầu V2 TV3 | Bằng chứng hiện tại | Status |
|---|---|---|
| Boot 3.2.5 / Java 21 | pom.xml; Maven compile 53 Java source + 5 test classes, Java 21.0.11 | TESTED |
| JWT, BCrypt, disabled account, ownership | SecurityConfig/AuthServiceImpl/RecordServiceImpl; 17 RecordApiIntegrationTest với H2/MockMvc | TESTED (H2) |
| Search bind owner và keyword, literal %, _, quotes | RecordRepository dùng JPQL named parameters + LOCATE; regression H2 giữ owner scope | TESTED (H2); PostgreSQL HTTP UNVERIFIED |
| Main vulnerable route default-off | Cả profile sqli-lab và flag true mới tạo controller; valid JWT trên main 404 trong regression | TESTED (H2/config) |
| Hai main node cùng image/DB/JWT, dữ liệu chéo, 403, node2 sau stop node1 | Test-TwoNodeIntegration kiểm tra image ID, JWT hai chiều, create/read hai chiều, ownership, stop có label ownership, health/read sau stop | IMPLEMENTED / runtime UNVERIFIED |
| Response byte[] PowerShell | Http-Response dùng UTF8 trước khi bind string; health/Call-Api/Parse-ApiJson dùng chung; mock string/byte[]/UTF-8 JSON PASS ở PS 5.1 và 7 | TESTED (mock) |
| Hibernate startup/probe fixed | So sánh byte nội dung với standalone Test-HibernateValidation-fixed: chỉ khác đường dẫn SQL; giữ nguyên | IMPLEMENTED; PostgreSQL phiên này UNVERIFIED |
| Least privilege + validate | Hai SQL init giữ nguyên; base và integration validate/show-sql false; dev opt-in phục hồi update/show SQL | IMPLEMENTED; quyền/schema PostgreSQL phiên này UNVERIFIED |
| prod profile | Không có application-prod.yml; chỉ có nhánh prod trong Logback, không phải cấu hình JPA/DB production | MISSING (không cần thêm; dùng integration) |
| SQLi runtime không dùng business identity/DB/network | Compose độc lập: lab identity DB + fixture DB tmpfs, một internal network, separate credentials/JWT; effective config assertions PASS | TESTED (config); runtime UNVERIFIED |
| Reader SELECT-only, fixture-only, timeout | SqliLabRepository/init-demo giữ nguyên; 5 config tests PASS; 5 PostgreSQL tests skipped | IMPLEMENTED / PostgreSQL UNVERIFIED |
| Request ID chống control characters/oversize; không log parser JWT | 11 MDC tests + 1 JWT logging test PASS; ID 1–64 ASCII allowlist, fallback UUID, MDC cleanup kể cả chain throw | TESTED |
| LB/Nginx failover, WAF SQLi block + CRS audit | Root vẫn HTTP Echo; không sửa các file TV1/TV2 | UNVERIFIED / ngoài phạm vi TV3 |

## Thay đổi và rủi ro

| File/nhóm file | Xử lý và lý do | Rủi ro/giới hạn |
|---|---|---|
| backend/scripts/Test-TwoNodeIntegration.ps1, Http-Response.ps1, Test-HttpResponse.ps1 | Chuẩn hóa UTF-8 mọi đường đọc Content; diagnostic chỉ status/type; bổ sung JWT/Record hai chiều và tùy chọn chạy HTTP lab | Regression mock PASS; Docker chưa chạy; không chứng minh Nginx failover |
| backend/src/main/resources/application.yml, application-dev.yml | Default validate/show-sql false/INFO; dev opt-in giữ workflow cũ | Local DB chưa có schema phải provision hoặc chọn dev; không chạy dev trên main/lab tích hợp |
| backend/docker-compose.sqli-lab.yml, .env.sqli-lab.example | Thay overlay cũ bằng lab độc lập ba service, identity giả/JWT riêng, hai DB tmpfs và TCP health sau init | Lệnh ghép Compose cũ không còn hợp lệ; login lab riêng; tmpfs mất dữ liệu khi recreate; runtime chưa kiểm chứng |
| backend/scripts/Test-SqliE2E.ps1, Test-BackendTests.ps1 | HTTP lab đăng ký/login riêng; kiểm tra token main/lab bị từ chối; dùng Compose/network mới | Các script HTTP/Docker vẫn cần host run |
| backend/scripts/Test-V2Contract.ps1, Test-V2Host.ps1 | Static effective config assertions; một runner tự tạo resource/secret/port ngẫu nhiên và cleanup phạm vi riêng | Host runner mới chỉ syntax checked; cần PS7, Docker Desktop Linux Engine và mạng tải dependency/image |
| MdcLoggingFilter.java, JwtAuthenticationFilter.java và hai test Java mới | Giới hạn header; bỏ raw JWT parser exception message | Không phải audit toàn bộ logging của ứng dụng/WAF; không ghi token/password/body vào diagnostic |
| backend/README.md, backend/docs/BACKEND_HANDOVER.md, WAF_INTEGRATION.md; docs/contract/api-endpoints.md và tài liệu này | Cập nhật hợp đồng, bỏ hướng dẫn topology cũ dễ nhầm, tách kết quả lịch sử và phiên hiện tại | TV1/TV2 phải thực thi tích hợp để chốt 4 demo |
| Test-HibernateValidation.ps1, Test-DatabaseInit.ps1, application-integration.yml, database/init/*.sql, core auth/Record | Giữ nguyên vì đã đúng với yêu cầu/source | PASS lịch sử SQL/Hibernate không thay thế bằng chứng source hiện tại |
| Untracked TwoNode-Diagnostic-REUPLOAD.ps1; root Compose/Nginx/WAF/.gitignore/README; standalone | Giữ nguyên, ngoài phạm vi hoặc thay đổi có trước | Không được suy ra backend đã thay Echo trong root stack |

## Kết quả thực thi phiên hiện tại

| Lệnh/kiểm tra | Môi trường | Kết quả |
|---|---|---|
| Maven -B -ntp test, repo cache trong backend/target/maven-cache | Windows; Temurin 21.0.11 tại C:\Users\Admin\.jdks; Maven 3.9.11 bundled IntelliJ; H2/MockMvc | BUILD SUCCESS: 39 total, 34 chạy PASS, 0 failures/errors, 5 PostgreSQL skipped |
| Đọc target/surefire-reports/TEST-*.xml | Source hiện tại, không lấy báo cáo standalone | Record 17; LabConfiguration 5; MDC 11; JwtLogging 1 PASS; LabPostgres 5 skipped |
| Test-HttpResponse.ps1 | Windows PowerShell 5.1 và pwsh 7 | PASS string/byte[] health/response/login JSON/UTF-8/null/malformed |
| Parser ParseFile cho toàn bộ backend/scripts/*.ps1 | PowerShell AST; bao gồm runner host mới | PASS cú pháp, không phải runtime E2E |
| Test-V2Contract.ps1 (docker compose config --format json, chỉ template placeholders) | CLI Compose, không cần Engine; không in resolved config | PASS schema, identity/JWT riêng, network internal, DB không publish, tmpfs, loopback API, init mount read-only |
| git diff --check | Working tree | PASS |
| docker version --format server version | Sandbox Codex, chỉ thử Engine một lần | FAIL hạ tầng: không có pipe dockerDesktopLinuxEngine; không chạy container |
| Maven lần đầu trong sandbox | Dependency chưa có cache | FAIL hạ tầng DNS Maven Central; sau khi chạy ngoài sandbox đã tải dependency và test PASS như trên |
| SQL init / Hibernate PostgreSQL / full lab HTTP / two-node Docker | Docker Engine không khả dụng | NOT RUN; host runner đã chuẩn bị |
| Nginx LB/failover / ModSecurity CRS | Không sửa/khởi chạy hạ tầng TV1/TV2 | NOT RUN |

Đường dẫn Maven thực tế: `C:\Program Files\JetBrains\IntelliJ IDEA 2026.1.3\plugins\maven\lib\maven3\bin\mvn.cmd`. Lệnh đã chạy từ backend: Maven đó với `-B -ntp -Dmaven.repo.local=<repo>\backend\target\maven-cache test`, JAVA_HOME=`C:\Users\Admin\.jdks\temurin-21.0.11`. Maven test đã compile source và tests; không tuyên bố Docker image build hoặc PostgreSQL validate PASS.

## Một lệnh host cho phần chưa chạy

Trên Windows host có Docker Desktop Linux Engine hoạt động, chạy đúng một lệnh sau. Không cần tạo .env hay điền secret; không đọc credentials thật từ standalone.

```powershell
& 'C:\Users\Admin\.cache\codex-runtimes\codex-primary-runtime\dependencies\native\powershell\pwsh.exe' -NoProfile -File 'D:\ProJect An Toan Thong TIn\Codex\CSATTT-BTL--Nhom9-integration\backend\scripts\Test-V2Host.ps1'
```

Runner build source hiện tại; tạo project Compose ngẫu nhiên chỉ gồm ba service lab; kiểm tra network/primary datasource; chạy full Maven với PostgreSQL opt-in và yêu cầu ít nhất 39 tests, 0 skips/errors/failures; chạy HTTP secure/lab và two-node. Mọi test account/record là mới. Chỉ container Maven không phục vụ HTTP có bridge ra ngoài để tải test-provider còn thiếu; vulnerable API chỉ có mạng internal riêng. Two-node dùng một network/DB/secret/image riêng cho cả hai main nodes. SQL init rồi Hibernate validate được thực hiện trong quá trình startup hai node; không chạy lại script Hibernate riêng không cần thiết.

Runner kiểm tra collision trước tạo tài nguyên, gắn label cho builder/test runner; two-node kiểm tra ownership label trước stop/cleanup; Compose cleanup chỉ project ngẫu nhiên đã kiểm tra không tồn tại. Không dùng down -v, prune, volume rm hay đọc/xóa volume nghiệp vụ. Nếu cleanup lỗi, chỉ báo đúng project/resource cần kiểm tra; không tự xóa tài nguyên ngoài phạm vi. Root application stack không được khởi chạy/chỉnh sửa.

## Bàn giao TV1/TV2 để đủ bốn demo

| Chủ sở hữu | Cấu hình/hành động cần bàn giao | Bằng chứng nghiệm thu |
|---|---|---|
| TV1 — hai main backend | Thay Echo bằng cùng image build context backend; port nội bộ 8080; DB_HOST=database, DB_PORT=5432, DB_NAME=blogdb; DB_USERNAME/DB_PASSWORD role app; cùng JWT_SECRET Base64 >=32 random bytes; SPRING_PROFILES_ACTIVE=integration; SQLI_DEMO_ENABLED=false | Hai image IDs trùng, health UP, JWT/Record dùng chéo và owner B 403; không in env/secrets |
| TV1 — schema/least privilege | Provision DB mới bằng 01-schema rồi 02-least-privilege, APP_DB_USERNAME/APP_DB_PASSWORD ở provisioning; DB_USERNAME/DB_PASSWORD cùng role ở app; không dùng postgres_admin để chạy app; không reinit volume cũ | Hibernate validate startup + health + quyền DML/sequence, không CREATE/schema ownership; không dùng fallback password hiện tại trong demo chia sẻ |
| TV1 — demo 1 LB/failover | Chốt upstream names/backend networks, health/failover/timeouts, phương án xác nhận node nhận request và stop node an toàn | Gọi qua cùng URL Nginx, thấy phân phối và tiếp tục hoạt động sau stop node1; bài two-node TV3 chỉ gọi trực tiếp, không thay thế chứng cứ này |
| TV2 — demo 2 WAF chặn SQLi | Inspect JSON POST /api/v1/secure/records/search (và route lab nếu chốt proxy riêng), Content-Type application/json, body {"keyword":"..."}; chốt CRS/version/mode/threshold/PL | Normal request thành công; DetectionOnly có audit hit; On block payload; đối chiếu rule ID, transaction/time/request ID và marker X-Blocked-By do WAF sở hữu; handler không nhận request bị block |
| TV1/TV2 — lab đối chứng | Chạy lab Compose độc lập; identity/DB/JWT riêng; proxy lab không nối vulnerable API vào business DB network; không public lab, không dùng token main ở lab | Normal alpha 1 fixture vs Boolean payload 3 fixtures; reader không đọc/ghi ngoài fixture; token dùng chéo main/lab 401; runtime kiểm chứng trước demo |
| TV2 + TV3/QA — demo 3 parameter binding | Khi WAF không chặn/DetectionOnly hoặc gọi trực tiếp local, gửi cùng payload tới secure route; tạo dữ liệu giả mới | SQLi là literal, 200 [] với fixture không chứa payload; scope owner giữ nguyên; ghi expected/actual + request ID |
| TV1/TV2 + QA — demo 4 IDOR | A tạo record, B đọc đúng ID qua proxy; cho phép request tới backend để phân biệt nguồn 403 | Backend 403 ownership khác WAF 403; có log backend tương ứng, không giả marker WAF |

Header correlation: Nginx sinh X-Request-ID hợp lệ (1–64 ASCII chữ/số/dot/underscore/hyphen, bắt đầu chữ/số), backend thay UUID nếu sai. Audit chia sẻ phải che Authorization, JWT, password, refreshToken và body nhạy cảm. Path API và JSON keyword giữ nguyên theo api-endpoints.md; backend không thêm marker WAF.
