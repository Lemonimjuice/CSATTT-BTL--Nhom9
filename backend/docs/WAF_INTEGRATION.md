> **Cập nhật V2 27/10/2026:** xem [hợp đồng hiện hành](../../docs/contract/tv3-v2-handover.md). Backend Docker E2E đã PASS; WAF/ModSecurity vẫn NOT RUN. Lab dùng identity DB/JWT riêng. Runner dùng plain HTTP gateway test, bỏ publish trực tiếp từ API và cấp port loopback ngẫu nhiên; gateway này không có WAF và không thay gateway TV1/TV2.

# Backend / ModSecurity integration contract

Tài liệu cho lab BTL Defense in Depth. Các ví dụ dùng dữ liệu giả, JWT của tài khoản thử nghiệm và HTTP local. ModSecurity/CRS và Nginx LB chưa được kiểm chứng với backend thật; kết quả WAF bên dưới là tiêu chí cần kiểm chứng sau tích hợp.

## 1. Luồng request và ranh giới dữ liệu

```text
Client -> Nginx/WAF (TV1/TV2) -> main Spring nodes -> DB nghiệp vụ
Client loopback -> HTTP test gateway -> lab Spring (JWT riêng) -> identity DB tạm
                                                             -> fixture DB tạm (JDBC reader riêng)
```

- Backend thường: `http://127.0.0.1:8080`; vulnerable route mặc định không tồn tại.
- HTTP lab trong runner: URL `http://127.0.0.1:<random>` được in sau khi xác minh active binding của gateway. Test override bỏ port API; API/DB chỉ ở internal network. Port 8081 trong base Compose không phải URL tái hiện runner. Profile `sqli-lab` và flag bật tường minh; không public lab ra Internet/tunnel.
- Lab database nằm trong container riêng, không publish cổng PostgreSQL; tài khoản truy vấn chỉ SELECT bảng `demo.records`. JDBC lab không dùng tài khoản/datasource nghiệp vụ.
- Toàn bộ lab API cũng không nhận credentials hoặc network nghiệp vụ: JPA/JWT user lookup dùng `sqli-lab-auth-db`, identity giả và key riêng. Token main/lab phải bị từ chối khi dùng chéo. TV1/TV2 cần chốt proxy lab riêng mà không nối lab API vào network chứa DB nghiệp vụ.
- WAF là lớp thêm vào. Secure search luôn phải giữ parameter binding và ownership khi WAF bị bypass hoặc tắt.
- Khi tích hợp, Docker/Nginx cần chặn truy cập backend trực tiếp từ bên ngoài và giữ lab trong mạng máy demo. Việc thay đổi cổng/firewall/Nginx phải được nhóm thống nhất.

## 2. HTTP contract

Mọi request search dùng `Content-Type: application/json` và `Authorization: Bearer <access_token>`. Token lấy từ `POST /api/v1/auth/login`; không ghi token/password vào ảnh chụp hoặc audit log chia sẻ.

| Method / path | Mục đích | Quyền | Kết quả bình thường |
|---|---|---|---|
| `POST /api/v1/secure/records/search` | Tìm chuỗi literal không phân biệt hoa/thường trong Record của chính người gọi | JWT hợp lệ | `200`, mảng tối đa 50 Record |
| `POST /api/v1/vuln/records/search` | Đối chứng SQLi trong lab riêng | JWT hợp lệ + lab được bật | `200`, mảng tối đa 50 dòng giả |
| `POST /api/v1/secure/records` | Tạo dữ liệu thử cho owner | JWT hợp lệ | `201`, Record vừa tạo |
| `GET /api/v1/secure/records/{id}` | Demo ownership | JWT hợp lệ + owner | `200`; người khác `403`; không tồn tại `404` |
| `POST /api/v1/auth/register` | Tạo tài khoản thử mới | Public | `201`; trùng username/email `409` |
| `POST /api/v1/auth/login` | Lấy token | Public | `200`; credentials sai/disabled `401` |
| `GET /actuator/health` | Liveness/readiness đơn giản | Public | `200`, `{"status":"UP"}` khi khỏe |

Search request giống nhau ở hai route:

```json
{"keyword":"alpha"}
```

`keyword` bắt buộc, không chỉ khoảng trắng, tối đa 200 ký tự. Secure search coi `%`, `_`, `'` là ký tự dữ liệu; không sử dụng chúng làm wildcard hoặc cú pháp SQL. Không có phân trang trong contract tạm thời; kết quả theo ID tăng dần, giới hạn 50. Lab từ chối dấu `;` để ngăn stacked statements; đây là containment cho lab, không phải biện pháp chống SQLi của secure API.

Response ví dụ (ID secure là động):

```json
[{"id":1,"content":"LAB-ONLY alpha report"}]
```

Không có kết quả: `200 []`. Request JSON sai, thiếu/blank/quá dài: `400`. JWT thiếu/sai/hết hạn: `401`. Với JWT hợp lệ, vulnerable route mặc định tắt trả `404`. Lab query vi phạm quyền/cú pháp/stacked statements trả `400 {"status":400,"message":"Demo query rejected"}`. Kiểm tra cô lập thất bại khi xử lý request hoặc mất kết nối lab trả `503 {"status":503,"message":"SQLi lab isolation check failed"}`; lỗi kiểm tra lúc startup làm lab API không khởi động. Không trả SQL, JDBC URL hay stack trace. Lỗi hạ tầng không được coi là kết quả SQLi thành công.

Backend ownership `403` có dạng:

```json
{"timestamp":"<server-time>","status":403,"message":"You do not have permission to read this record","path":"/api/v1/secure/records/<id>"}
```

## 3. Dữ liệu demo và test cases

Lab chỉ có fixture cố định:

| id | content |
|---|---|
| 1 | `LAB-ONLY alpha report` |
| 2 | `LAB-ONLY beta note` |
| 3 | `LAB-ONLY gamma archive` |

Để đối chiếu, tạo Record secure cho User A với cùng content của dòng 1 qua API; tạo một Record khác cho User B. ID secure không nhất thiết là 1. Tìm kiếm secure chỉ thấy dữ liệu thuộc A, dù B có content khớp.

Các kết quả dưới đây áp dụng cho fixture trên, khi gọi backend trực tiếp và WAF chưa can thiệp:

| Test | JSON `keyword` | Secure | Vulnerable lab |
|---|---|---|---|
| Chuỗi thường | `alpha` | `200`, Record khớp của A | `200`, dòng 1 |
| Khác hoa/thường | `ALPHA` | `200`, cùng kết quả `alpha` | Tùy phép LIKE của lab; không dùng làm tiêu chí SQLi |
| Không khớp | `not-present-in-fixtures` | `200 []` | `200 []` |
| Dấu nháy | `O'Reilly` | Chuỗi literal, `200`, không lỗi SQL | Có thể `400` do query cố tình yếu |
| Boolean SQLi | `' OR 1=1 -- ` | `200 []` nếu không lưu literal này | `200`, cả 3 dòng giả |
| Wildcard | `%` hoặc `_` | Chỉ tìm ký tự literal | LIKE có thể mở rộng kết quả trong fixture |
| Thử bảng thật | `' UNION SELECT id, username FROM public.users -- ` | `200 []` với fixture | `400`, không đọc được `users` |
| Không JWT / JWT sai | bất kỳ hợp lệ | `401` | `401` |
| Trống / dài 201 ký tự | blank / chuỗi dài | `400` | `400` khi lab bật |
| Stacked statement | chứa `;` | Chuỗi literal, `200` | `400`, containment trước khi execute |

Không chạy payload UPDATE/DELETE/DROP, đọc file hệ thống hoặc stress trong buổi demo. Mục tiêu đối chiếu là thay đổi tập kết quả SELECT trên dữ liệu giả. Automated test lab đã có một case `pg_sleep` để xác nhận timeout truy vấn 2 giây; không cần lặp stress qua WAF. Kiểm tra quyền DB trực tiếp thuộc QA lab, không cần tấn công dữ liệu nghiệp vụ.

## 4. Yêu cầu cấu hình WAF

Thành viên WAF cần cấu hình JSON request-body inspection cho hai route POST search, `Content-Type: application/json`, và bật OWASP CRS SQLi rules. Request có JWT hợp lệ để phân biệt WAF chặn với lỗi authentication.

Đề xuất vận hành, chưa được áp dụng:

1. Chốt phiên bản ModSecurity/connector/CRS, anomaly threshold, paranoia level và body-size limit; ghi vào cấu hình tích hợp.
2. Chạy `DetectionOnly` local để xác nhận parser/rule hit với payload; sau đó chuyển `On` cho phần demo chặn.
3. Khi WAF chặn, trả HTTP `403` kèm response header `X-Blocked-By: waf`; backend không tự thêm header này. Ghi CRS rule ID, transaction ID, timestamp và request ID vào audit log.
4. Nginx sinh request ID và chuyển `X-Request-ID` tới backend. Backend chỉ giữ ID 1–64 ký tự `[A-Za-z0-9][A-Za-z0-9._-]*`, input khác được thay UUID. Không tin response header giả do client đưa vào; Nginx phải sở hữu marker WAF.
5. Che Authorization, password, refresh token và dữ liệu Record trong log chia sẻ; không log nguyên toàn bộ request/response auth.

Không dùng riêng HTTP `403`, hình dạng body hoặc sự hiện diện `X-Request-ID` để kết luận nguồn chặn. Backend ownership cũng trả `403`. `MdcLoggingFilter` hiện chạy trước Spring Security; 401/403 do backend và exception trong luồng đã vào filter có access event/Request ID, không ghi JWT/body. WAF chặn trước backend không đi qua filter này. Bằng chứng WAF vẫn cần marker do Nginx tạo **và** CRS audit tương ứng; không suy ra WAF PASS chỉ từ status hoặc sự thiếu/vắng log backend.

## 5. Trình tự kiểm thử tích hợp

1. Chạy backend mặc định, health UP; đăng ký hai tài khoản thử mới, login, xác nhận auth/ownership theo `BACKEND_HANDOVER.md`.
2. Gửi normal và Boolean SQLi tới secure route trực tiếp; xác nhận `200` và tập kết quả đúng owner. Ghi status, số dòng và request ID, không ghi JWT.
3. Chỉ khi kiểm tra cô lập DB đạt, chạy lab tùy chọn; xác nhận `alpha` trả 1 dòng, Boolean SQLi trả 3 dòng, UNION bảng thật không trả dữ liệu, URL lab chỉ truy cập local.
4. Đặt Nginx/WAF local trước lab theo topology nhóm đã chốt. Lặp lại cùng body/header qua WAF ở DetectionOnly: có CRS hit, request vẫn đến backend.
5. Chuyển WAF On: normal request vẫn tới backend; SQLi dự kiến `403` với marker WAF và CRS rule ID. Không sửa backend để giả lập WAF block.
6. Lặp auth/Record ownership qua WAF; backend `403` của User B phải phân biệt được với `403` do CRS. Kiểm tra false positive với content hợp lệ có dấu nháy.
7. Ghi ảnh/log đã che secret, phiên bản image/config/rule, request ID, expected/actual. Dừng hai service lab khi hoàn tất; giữ PostgreSQL nghiệp vụ và volumes.

## 6. Cần nhóm trưởng thống nhất

- URL upstream, cổng chỉ local, Docker networks và cách không để người ngoài bypass Nginx; không public lab.
- Contract search tạm thời: tên `keyword`, cap 50, độ dài 200, status/error schema; có cần pagination sau demo không.
- JWT/role và tài khoản test do ai chuẩn bị; đồng bộ secret local giữa backend instances, không lưu secret trong Git.
- Phiên bản CRS, mode, threshold/paranoia level; phạm vi request body và quy trình xử lý false positive.
- Marker/error page WAF, request ID/audit-log fields, thời gian lưu bằng chứng; không đưa token/password vào báo cáo.
- Phạm vi pentest: chỉ máy lab, fixture giả và tài khoản mới; các demo WAF phải được thực thi rồi mới đánh dấu đạt.

## 7. Trạng thái kiểm chứng

Docker E2E hardening mới ngày 27/10/2026 kết thúc với exit code 0: Maven 152/152, HTTP secure/lab 42/42 và two-node HTTP 12/12 PASS. Lab HTTP qua gateway loopback, identity/DB/JWT separation, network isolation và cleanup đã chạy thật và PASS. Normal alpha trả 1 fixture; Boolean SQLi trả 3 fixture qua gateway, minh chứng gateway test không chặn payload. Backend audit hiện dùng peer IP, không tin forwarded IP headers khi chưa chốt proxy trust. Chi tiết tại [Feature Freeze](FEATURE_FREEZE.md), [hợp đồng V2](../../docs/contract/tv3-v2-handover.md) và [gateway test](SQLI_TEST_GATEWAY.md).

Chưa có bằng chứng ModSecurity/CRS end-to-end trong repository này. Các expected WAF `403` ở mục 4–5 vẫn là tiêu chí tích hợp, không phải kết quả đã chạy.
