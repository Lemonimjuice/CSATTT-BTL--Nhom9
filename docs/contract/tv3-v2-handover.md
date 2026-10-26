# Bàn giao Backend V2 cho TV1/TV2 — 27/10/2026

Nhánh bàn giao: `feat/tv3-backend`. Phạm vi: backend và hợp đồng TV3. Gateway HTTP trong bộ test là tài nguyên tạm để kiểm thử, không phải WAF/ModSecurity hoặc gateway production của TV1/TV2. Không thay đổi schema, JWT contract hoặc API endpoints trong phần bổ sung E2E.

## Kết quả Docker E2E đã thực thi

Lần chạy cuối của `backend/scripts/Test-V2Host.ps1` trên Docker Engine **29.9.2**, Compose **v5.6.1** kết thúc với **exit code 0**. Java 21 / Maven chạy trong builder của `backend/Dockerfile`, PostgreSQL 16 thật cho lab và hai main node.

| Hạng mục | Bằng chứng | Kết quả |
|---|---|---|
| Maven | Record API 17; JWT logging 1; SQLi lab PostgreSQL 5; lab configuration 5; MDC 11 | **39 PASS / 0 FAIL / 0 ERROR / 0 SKIPPED** |
| HTTP Secure API và SQLi Lab | `Test-SqliE2E.ps1`, được runner gọi với URL main và gateway lab thực tế | **30/30 PASS** |
| Two-node HTTP | `Test-TwoNodeIntegration.ps1`; cả hai startup health UP | **12/12 assertions PASS** |
| Shared JWT / Record | JWT và tạo/đọc Record hai chiều giữa hai main node dùng cùng image ID và DB | **PASS** |
| IDOR | User khác đọc cùng Record trên cả hai node nhận 403 | **PASS** |
| Node survival | Stop Node1 sau kiểm tra ownership label; Node2 vẫn health UP và đọc đúng Record | **PASS** |
| SQLi lab HTTP | Normal alpha trả 1 fixture; Boolean SQLi trả 3; các UNION bảng ngoài fixture/catalog bị từ chối | **PASS** |
| JWT main/lab riêng | Login riêng trong lab; token dùng chéo main/lab trả 401 | **PASS** |
| Isolation / publishing | API và hai DB internal-only, không requested/active host bindings; chỉ gateway trên edge riêng, chỉ publish IPv4 loopback ngẫu nhiên | **PASS** |
| Cleanup | Runner cleanup và inventory riêng theo project/run label xác nhận không còn tài nguyên test | **PASS** |
| Nginx LB/failover qua proxy TV1 | Chưa nằm trong bài kiểm thử direct-node | **NOT RUN** |
| ModSecurity/OWASP CRS blocking và audit | Gateway test không có WAF; cần TV2 chạy tích hợp | **NOT RUN** |

Không còn FAIL trong lần E2E cuối. Không dùng kết quả cũ 34 PASS/5 skipped để mô tả bộ kiểm thử cuối này. Tests H2/MockMvc vẫn nằm trong Maven suite; chỉ các cases PostgreSQL/HTTP tương ứng là bằng chứng runtime PostgreSQL.

Bằng chứng vận hành đã đối chiếu: project `tv3v2e5e683feb2bd`, two-node run `cdd1b3a4906f49219de382f6f314ca2d`. Log tại máy chạy được giữ trong `backend/logs/` (Git ignore); log và diagnostic không nằm trong commit. Các run ID và port là dữ liệu minh chứng của phiên đã cleanup, không phải cấu hình để tái sử dụng.

## Tái hiện từ repository

Yêu cầu: PowerShell 7 (`pwsh` trong PATH), Docker Desktop Linux Engine, Compose hỗ trợ `!reset`, Internet để tải image/dependency khi chưa có cache. Chạy từ root checkout:

```powershell
pwsh -NoProfile -File ./backend/scripts/Test-V2Host.ps1
```

Không cần tạo `.env` hay điền credentials để chạy runner: secrets ngẫu nhiên được sinh trong process, đưa vào Docker theo tên biến và khôi phục environment khi kết thúc. Runner chỉ dùng `.env.sqli-lab.example` làm mẫu interpolation, không đọc `.env` thật. Không in auth bodies, JWT/password hoặc resolved Compose environment.

Runner build source hiện tại; tạo project ngẫu nhiên với ba service lab và một gateway HTTP test. Nó kiểm tra effective config trước tạo tài nguyên, xác minh Engine bindings và network membership, gọi lab health qua gateway, chạy Maven PostgreSQL opt-in, HTTP secure/lab và two-node. Schema/grants được áp dụng trên PostgreSQL mới; hai main node khởi động với profile `integration`/Hibernate validate và cùng role ứng dụng.

Chỉ cleanup resource thử nghiệm đã tạo: collision checks, ownership labels, Compose project riêng; không prune, không xóa volume nghiệp vụ, không chạy root application stack. Sau cleanup container/node không còn chạy và port được giải phóng. Shared base images có thể còn dưới dạng cache.

Kiểm tra tĩnh đã PASS: toàn bộ PowerShell AST, `Test-HttpResponse.ps1`, `Test-DockerLoopback.ps1` (18 cases, PS5.1 và PS7), `Test-LabTestGateway.ps1` (effective override và 9 topology không an toàn bị từ chối), `Test-V2Contract.ps1`, `nginx -t` với đúng non-root/read-only/cap-drop settings, và Git diff whitespace checks. Không cần chạy lại Docker E2E chỉ để thay đổi tài liệu bàn giao.

## Ranh giới gateway thử nghiệm

`backend/docker-compose.sqli-lab.test.yml` được merge sau base lab Compose **chỉ trong runner**. Nó reset ports của API bằng `!reset []`, thêm `sqli-test-gateway` nối mạng lab internal và edge bridge riêng, publish `127.0.0.1:<random>:8080`. API và hai DB không vào edge. Gateway không nhận DB/JWT credentials, không mount Docker socket, chỉ proxy tới upstream lab API cố định, không có rule/marker WAF. Chi tiết tại [SQLI_TEST_GATEWAY.md](../../backend/docs/SQLI_TEST_GATEWAY.md).

Trên Engine đã kiểm thử, container chỉ nối internal network có thể giữ yêu cầu port trong HostConfig nhưng không có active binding. Runner xác minh `NetworkSettings.Ports`, không coi HostConfig hoặc output `compose port` là bằng chứng port đã hoạt động. Bài test không nới bind sang public và không thay base lab Compose hay hợp đồng production.

## Hợp đồng và công việc còn lại cho TV1/TV2

| Chủ sở hữu | Cấu hình/việc cần bàn giao | Bằng chứng nghiệm thu còn cần |
|---|---|---|
| TV1 — main nodes | Cùng image build context `backend/`, container port 8080; `DB_HOST=database` theo service nhóm, `DB_PORT=5432`, `DB_NAME=blogdb`, cùng app `DB_USERNAME`/`DB_PASSWORD`, cùng `JWT_SECRET` Base64 >=32 random bytes; `SPRING_PROFILES_ACTIVE=integration`, `SQLI_DEMO_ENABLED=false` | Khởi động main stack đã tích hợp; không dùng tên `postgres` của standalone cũ hoặc provisioning owner cho ứng dụng |
| TV1 — schema | DB mới: `01-schema.sql` rồi `02-least-privilege.sql`; provisioning nhận `APP_DB_USERNAME`/`APP_DB_PASSWORD`; app dùng cùng role với validate/show-sql false | Quy trình provision/migration phù hợp volume nhóm; không chạy init trên volume nghiệp vụ cũ |
| TV1 — demo LB/failover | Chốt upstream, health/timeouts và dấu hiệu xác nhận node nhận request | Gọi qua cùng URL Nginx, thấy phân phối và tiếp tục hoạt động sau stop node1; bài direct-node PASS không thay thế bài này |
| TV2 — WAF | Inspect JSON `keyword` ở POST `/api/v1/secure/records/search`, và route lab nếu chốt proxy lab riêng; chốt CRS/version/mode/threshold/PL | Normal request thành công; DetectionOnly có rule hit; On chặn SQLi; marker do WAF sở hữu và audit rule ID/transaction/request ID; handler không nhận request bị block |
| TV1/TV2 — production lab routing | Identity/DB/JWT lab riêng, không nối vulnerable API vào business DB network, không public lab | Chốt gateway triển khai riêng; không dùng gateway test này làm bằng chứng ModSecurity |
| TV1/TV2 + QA — parameter binding / IDOR qua proxy | Cùng payload SQLi qua secure route khi WAF cho qua; A tạo Record, B đọc ID | Literal search giữ owner scope; phân biệt backend IDOR 403 với WAF 403 bằng audit và correlation |

API paths/JSON/status theo [api-endpoints.md](api-endpoints.md); schema theo [db-schema.md](db-schema.md). Default và `integration` dùng validate/show-sql false. `dev` chỉ phục hồi workflow phát triển auto-DDL; không dùng khi tích hợp. Không có `application-prod.yml`; nhánh prod trong Logback không thay thế profile tích hợp.

Nginx sinh `X-Request-ID` 1–64 ký tự ASCII chữ/số/dot/underscore/hyphen, bắt đầu bằng chữ/số. Backend thay UUID nếu input sai. Audit chia sẻ phải che Authorization, JWT/password, refreshToken và body nhạy cảm. Các lỗi P1, tính năng mới và thay đổi TV1/TV2 nằm ngoài lần bàn giao E2E này.
