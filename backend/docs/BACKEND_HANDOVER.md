> **Repository nhóm:** tài liệu này lưu contract và bằng chứng từ backend standalone. Các lệnh Docker Compose bên dưới dùng service `postgres`/`blog-api` của repo nguồn, chưa áp dụng trực tiếp cho Compose nhóm đang dùng HTTP Echo. Xem `backend/README.md` trước khi chạy.

# Backend handover — BTL Defense in Depth

## 1. Phạm vi backend

- Java 21, Spring Boot 3.2.5, Spring Security, JPA/Hibernate, PostgreSQL 16, Maven và Docker Compose.
- Register/login, BCrypt, JWT access token, refresh/logout. JWT filter và refresh từ chối tài khoản disabled.
- Secure Record create/read/search; owner lấy từ principal JWT, không tin `ownerId` client. Người khác đọc Record theo ID nhận `403`; thiếu token `401`; không tồn tại `404`.
- Secure search bind tham số JPA, tìm literal không phân biệt hoa/thường, chỉ Record của người gọi, tối đa 50 dòng.
- Lab SQLi đối chứng riêng, mặc định tắt; profile + flag tường minh, datasource reader và PostgreSQL chỉ chứa dữ liệu giả. Không phải API nghiệp vụ.
- Blog API cũ được giữ; PUBLISHED đọc công khai; DRAFT/ARCHIVED đọc theo owner/ADMIN; `/posts/me` cần đăng nhập.
- Baseline trước SQLi: `afbb2ef`; sửa auth/authorization: `48bd9ed`. Commit của phần SQLi xem Git log/kết quả bàn giao hiện tại.

Các file chính: `RecordController`, `RecordServiceImpl`, `RecordRepository`, `RecordRequests`, `SecurityConfig`, package `demo`, `docker-compose.sqli-lab.yml`, `docker/sqli-lab/`, và các regression tests dưới `src/test`.

## 2. Chạy backend mặc định

Chạy từ root repository bằng PowerShell. `.env` cục bộ phải có DB credentials đang khớp volume hiện tại và `JWT_SECRET` hợp lệ. Không thay credentials/JWT secret để tái hiện demo. Chỉ khi cài mới chưa có `.env`, copy `.env.example` rồi thay placeholders bằng giá trị local.

```powershell
docker compose config --quiet
docker compose up -d --build postgres blog-api
docker compose ps
Invoke-RestMethod http://127.0.0.1:8080/actuator/health
```

Nếu chỉ áp dụng code image mới lên hệ thống đang chạy:

```powershell
docker compose build blog-api
docker compose up -d --no-deps --force-recreate blog-api
```

Chỉ backend bị recreate, có gián đoạn ngắn. PostgreSQL dùng volume sẵn có. Không dùng `down -v`, `volume rm`, SQL reset hoặc script init trên database nghiệp vụ. Đổi `POSTGRES_PASSWORD` trong Compose không đổi password của volume đã khởi tạo.

Maven bằng Docker, không cần Maven/JDK trên Windows:

```powershell
docker build --target builder -t btl-backend-tests .
./scripts/Test-BackendTests.ps1
```

Dockerfile build image ứng dụng có `-DskipTests`; build image thành công không đồng nghĩa test đã chạy. Phải đọc kết quả lệnh `mvn test` riêng.

## 3. Bật lab tùy chọn

Chỉ chạy trên máy demo local. `.env.sqli-lab.example` là mẫu; tạo `.env.sqli-lab` chứa hai password lab ngẫu nhiên riêng, không dùng DB/JWT secret nghiệp vụ. Giữ file này ngoài Git. Tên biến chính xác xem mẫu và compose overlay.

```powershell
# Chỉ tạo mẫu khi chưa có file local; thay placeholders trước khi chạy.
if (-not (Test-Path .env.sqli-lab)) { Copy-Item .env.sqli-lab.example .env.sqli-lab }
docker compose --env-file .env --env-file .env.sqli-lab -f docker-compose.yml -f docker-compose.sqli-lab.yml --profile sqli-lab config --quiet
docker compose --env-file .env --env-file .env.sqli-lab -f docker-compose.yml -f docker-compose.sqli-lab.yml --profile sqli-lab up -d --build sqli-lab-db sqli-lab-api
docker compose --env-file .env --env-file .env.sqli-lab -f docker-compose.yml -f docker-compose.sqli-lab.yml --profile sqli-lab ps
```

Lab API: `http://127.0.0.1:8081`. API thường ở 8080 vẫn tắt vulnerable route. Không thêm port publish cho lab DB; không đổi bind lab API sang `0.0.0.0`; không dùng tunnel public. API lab dùng DB nghiệp vụ cho auth/secure routes và **connection reader riêng** cho vulnerable route. Chỉ tạo dữ liệu/tài khoản mới cho kiểm thử.

Lab bật khi có cả profile `sqli-lab` và `SQLI_DEMO_ENABLED=true`; mặc định flag false. `application-sqli-lab.yml` đọc `SQLI_DEMO_DB_URL`, `SQLI_DEMO_DB_USERNAME`, `SQLI_DEMO_DB_PASSWORD`. Overlay đặt URL `jdbc:postgresql://sqli-lab-db:5432/sqli_lab`, user `sqli_demo_reader` và password từ `SQLI_LAB_READER_PASSWORD`. `.env.sqli-lab` chứa `SQLI_LAB_ADMIN_PASSWORD` và `SQLI_LAB_READER_PASSWORD` ngẫu nhiên, khác nhau.

Lab database không chứa `users`, `refresh_tokens`, `secure_records` nghiệp vụ; fixture chỉ có ba dòng `LAB-ONLY`. Reader không có quyền ghi, tạo database/role/schema/temp hay đọc bảng ứng dụng khác. Backend kiểm tra điều kiện DB lúc khởi động và mỗi connection trước khi xử lý input; nếu kiểm tra startup không đạt, lab API không khởi động. Bảng hệ thống PostgreSQL có thể có metadata public; catalog credential `pg_authid` bị bảo vệ. Không tuyên bố mọi bảng hệ thống đều vô hình.

Connection lab read-only, connect/socket timeout 5 giây, query timeout 2 giây và tối đa 50 dòng. Dấu `;` bị từ chối để ngăn stacked statements tự thay đổi reader; Boolean/UNION SQLi vẫn cố tình hoạt động trên fixture. Đây là containment, không thay thế parameter binding. Query bị từ chối trả `400 {"status":400,"message":"Demo query rejected"}`; mất hạ tầng/kiểm tra cô lập runtime thất bại trả `503 {"status":503,"message":"SQLi lab isolation check failed"}`. Container lab DB giới hạn 512 MB/1 CPU/128 PID; API 768 MB/1 CPU/256 PID.

Lab dùng storage tạm; fixture có thể mất khi container lab bị recreate. Dừng lab sau demo, không dừng/xóa PostgreSQL nghiệp vụ:

```powershell
docker compose --env-file .env --env-file .env.sqli-lab -f docker-compose.yml -f docker-compose.sqli-lab.yml --profile sqli-lab stop sqli-lab-api sqli-lab-db
```

Để chạy đủ suite có kiểm tra PostgreSQL thật, bật lab DB rồi chạy runner PowerShell 7. Runner tự xác định Compose networks, đọc riêng reader password từ file ignored, đưa vào process env rồi khôi phục; không in hoặc truyền giá trị secret trong đối số CLI:

```powershell
./scripts/Test-BackendTests.ps1 -WithLab
# Nếu đã build builder image bằng tên khác:
./scripts/Test-BackendTests.ps1 -WithLab -Image blog-api-test-builder
```

Runner `-WithLab` đặt `SQLI_LAB_TEST_ENABLED=true`, `SQLI_DEMO_DB_URL`, `SQLI_DEMO_DB_USERNAME`, `SQLI_DEMO_DB_PASSWORD` cho test container. `SqliLabPostgresTest` chỉ chạy khi opt-in này bật. Nếu không có `-WithLab`, **5 tests PostgreSQL sẽ skipped**; không được coi lần chạy đó là bằng chứng cô lập PostgreSQL. Test URL chỉ được trỏ DB lab riêng, không dùng database nghiệp vụ.

## 4. API contract cho QA/WAF

| Request | JSON body | Expected |
|---|---|---|
| `POST /api/v1/auth/register` | `{"username":"<user-moi>","email":"<email-test>","password":"<password-local>"}` | `201`, auth response; trùng `409` |
| `POST /api/v1/auth/login` | `{"username":"<user>","password":"<password-local>"}` | `200`, `accessToken`, `refreshToken`, `tokenType`, `user` |
| `POST /api/v1/auth/refresh` | `{"refreshToken":"<refresh-token>"}` | `200`; sai/hết hạn/disabled `401` |
| `POST /api/v1/auth/logout` | `{"refreshToken":"<refresh-token>"}` | `204`; thu hồi refresh token |
| `POST /api/v1/secure/records` | `{"content":"LAB-ONLY alpha report"}` | JWT; `201 {"id":<id>,"content":"..."}` |
| `GET /api/v1/secure/records/{id}` | Không body | JWT; owner `200`, user khác `403`, ID thiếu `404` |
| `POST /api/v1/secure/records/search` | `{"keyword":"alpha"}` | JWT; `200 [{"id":<id>,"content":"..."}]`, chỉ own records |
| `POST /api/v1/vuln/records/search` | Cùng search body | JWT + lab bật; `200`, chỉ fixture giả; lab tắt `404` với JWT hợp lệ |

Search `keyword`: bắt buộc, không blank, dài tối đa 200; response tối đa 50; không khớp `200 []`. Dùng header `Authorization: Bearer <accessToken>` và JSON content type. Thiếu/sai/hết hạn JWT ở Record/search `401`; malformed JSON/validation `400`. Không có API nào yêu cầu client gửi owner.

Chi tiết SQLi payload/status và phân biệt WAF/backend `403`: xem [WAF_INTEGRATION.md](WAF_INTEGRATION.md).

Script HTTP E2E có sẵn cho PowerShell 7:

```powershell
./scripts/Test-SqliE2E.ps1 -BaseUrl http://localhost:8080 -LabBaseUrl http://localhost:8081
```

Script chỉ chấp nhận URL local, tạo account/Record ngẫu nhiên mới và in case/status, không in password/JWT/response auth. Có thể bỏ `-LabBaseUrl` để chỉ test backend mặc định. Script không xóa dữ liệu cũ.

## 5. Tái hiện bốn demo

### Demo 1 — Authentication/JWT

1. Tạo hai user A/B mới qua register; login cả hai. Lưu token trong biến/API client local, không in vào báo cáo.
2. Với token A, tạo Record `{"content":"LAB-ONLY alpha report"}` và lưu ID.
3. Đọc bằng token A → `200`; không token hoặc JWT giả → `401`.
4. Disabled-account và refresh-disabled được regression test riêng. Không sửa tài khoản cũ trong DB để demo; nếu cần test HTTP disabled, chỉ dùng account test mới và quy trình đã được duyệt.

### Demo 2 — Ownership/IDOR

1. A tạo Record; B đọc ID đó → `403` từ backend.
2. A đọc chính ID đó → `200`; A đọc ID không tồn tại → `404`.
3. Client gửi `ownerId` khác trong request create không chuyển owner. Tìm kiếm với JWT B không thấy Record của A, dù keyword trùng.

### Demo 3 — Parameterized SQLi và lab đối chứng

1. Trên secure API, A search `{"keyword":"alpha"}` → chỉ dòng khớp của A.
2. Search `{"keyword":"' OR 1=1 -- "}` → `200 []` với dữ liệu mẫu; logic truy vấn/ownership không đổi. Dấu `%`/`_` được coi literal.
3. Xác minh vulnerable route ở backend mặc định không truy cập được. Chỉ bật lab theo mục 3 khi DB restriction/loopback đã đạt.
4. Trên lab 8081, cùng JWT/normal body `alpha` → 1 dòng giả; cùng Boolean payload → 3 dòng giả. Không dùng kết quả này để khẳng định secure endpoint có lỗi.
5. Thử UNION `public.users` trong lab → bị từ chối, không trả dữ liệu thật. Đồng thời xác minh connection reader và quyền DB, không chỉ dựa vào body HTTP.

### Demo 4 — WAF thêm một lớp chặn (chờ tích hợp)

1. Thành viên WAF đặt Nginx/ModSecurity/CRS trước lab local, xác nhận normal request `200`.
2. DetectionOnly: payload có rule hit nhưng vẫn tới backend. On: cùng payload dự kiến `403` do WAF.
3. Ghi marker `X-Blocked-By: waf`, CRS rule ID/audit transaction/request ID và chứng minh request không tới handler backend.
4. Lặp demo 1/2 qua proxy để bảo đảm auth/ownership vẫn hoạt động. `403` backend không được tính là WAF chặn thành công.

Demo 4 là kế hoạch, chưa được kiểm chứng cho tới khi có Nginx/ModSecurity chạy thực tế.

## 6. Phân công tích hợp

| Thành viên | Việc cần làm |
|---|---|
| Docker/Nginx | Chốt upstream/network/cổng, không public backend/lab, giữ volume DB; healthchecks; đồng bộ JWT secret giữa backend instances qua env; không tự đổi password volume cũ; giới hạn tài nguyên lab |
| WAF | JSON parser + CRS SQLi rules cho hai POST search; DetectionOnly rồi On; chọn threshold/paranoia level; marker WAF + audit/request correlation; che secret trong logs |
| QA/Pentest | Tài khoản/dữ liệu mới, chạy auth/ownership/SQLi/default-off/isolation tests; so sánh direct vs proxy; ghi expected/actual/status/row count/rule ID; kiểm tra false positives; chỉ pentest lab local |
| Nhóm trưởng | Chốt contract cuối, phạm vi demo và quyền quản lý, topology hai backend, trách nhiệm quản lý env và bằng chứng, tiêu chí nghiệm thu |

## 7. Phần còn thiếu và giới hạn

- WAF/Nginx và load balancing giữa hai backend instances chưa được triển khai/kiểm chứng trong lượt SQLi này. API lab dùng chung PostgreSQL nghiệp vụ cho auth nhưng phục vụ mục đích đối chứng, không phải một bài kiểm thử load balancing.
- Contract search là tạm thời, chưa có pagination, chưa phải bài kiểm tra hiệu năng hoặc security audit toàn hệ thống.
- DB nghiệp vụ hiện dùng auto-DDL `update`; migration/schema governance, rotation secrets, hardening ports/role production cần kế hoạch riêng, không được suy ra đã hoàn tất từ lab.
- Các tính năng Blog ngoài regression liên quan không nằm trong phạm vi hoàn thiện SQLi.
- WAF không thay thế parameter binding, ownership hoặc authentication. SQLi payload có thể trả `200 []` hợp lệ ở secure route khi gọi trực tiếp.

## 8. Bằng chứng thực thi

Kết quả đã thực thi trong lượt triển khai SQLi, ngày 2026-10-26:

| Hạng mục | Trạng thái hiện tại |
|---|---|
| Toàn bộ automated Maven tests trong Docker, có PostgreSQL lab opt-in | **27 tests; failures 0, errors 0, skipped 0**: `RecordApiIntegrationTest` 17, `SqliLabConfigurationTest` 5, `SqliLabPostgresTest` 5 |
| Script chạy tests bàn giao | **Đạt**: `scripts/Test-BackendTests.ps1 -WithLab -Image blog-api-test-builder` đã chạy lại đủ 27 tests, 0 failures/errors/skipped |
| Role/grants/read-only PostgreSQL lab | **Đạt**: chỉ SELECT fixture, không ghi/create/temp/membership; normal 1 dòng và Boolean payload 3 dòng |
| Đọc dữ liệu ngoài fixture, stacked statement, timeout | **Đạt**: `users`, `refresh_tokens`, `secure_records`, `pg_authid` bị từ chối; stacked bị từ chối; `pg_sleep` bị cancel bởi query timeout 2 giây |
| Compose config / default safety | **Đạt** `config --quiet`; overlay giữ nguyên hiệu lực `postgres`/`blog-api`, DB lab không publish port, network internal + tmpfs, API bind `127.0.0.1:8081` |
| Build image ứng dụng | **Đạt** `docker compose build` cho backend chính và lab API; chỉ recreate `blog-api`, khởi động lab API với `--no-deps`; ID/StartedAt PostgreSQL nghiệp vụ không đổi |
| HTTP E2E trên PostgreSQL thật | **26 cases đạt** từ `scripts/Test-SqliE2E.ps1 -BaseUrl http://localhost:8080 -LabBaseUrl http://localhost:8081`; snapshot sau test: cả hai API và hai PostgreSQL healthy |
| HTTP auth/Record | Register `201`, login `200` cho A/B; Record create/read `201/200`, non-owner `403`, missing `404`, thiếu/sai JWT `401`; `/posts/me` anonymous `401`; health `200` |
| HTTP secure search/default-off | Normal `200`, đúng 1 dòng own-record dù user khác lưu content trùng; Boolean SQLi `200 []`; thiếu JWT `401`, blank `400`; vulnerable route ở backend chính `404` |
| HTTP lab SQLi/isolation | Alpha `200`, 1 dòng giả; Boolean payload `200`, 3 dòng giả; UNION `users`/`refresh_tokens`/`secure_records`/`pg_authid` đều `400`; thiếu JWT `401`, blank `400` |
| Lưu dữ liệu và trạng thái cuối | SQL read-only xác nhận 2 Record HTTP thử mới đã lưu trong PostgreSQL; sau test đã stop riêng `sqli-lab-api`/`sqli-lab-db`, backend chính và PostgreSQL vẫn healthy, health `UP` |
| ModSecurity/CRS integrated E2E | Chưa triển khai |

Không coi việc có test source, response mẫu hoặc Docker build với `-DskipTests` là bằng chứng test đã đạt.
