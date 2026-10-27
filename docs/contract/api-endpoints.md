# TV3 API contract

> **Cập nhật tích hợp nhóm 27/10/2026.** Hợp đồng gốc do TV3 viết; các chỗ thay đổi theo thiết kế nhóm
> (cụm `/vuln` chạy trên 2 node chính, IP thật qua Nginx, ẩn danh đọc bài riêng tư trả `401`) được ghi
> ngay tại dòng tương ứng và ở mục cuối. Lý do: [docs/decisions.md](../decisions.md).

Container port: 8080. JSON requests use `Content-Type: application/json`. Protected requests use `Authorization: Bearer <accessToken>`.

| Method and path | Request | Expected response | Auth |
|---|---|---|---|
| `POST /api/v1/auth/register` | `{ "username":"userA", "email":"userA@example.test", "password":"<test-password>" }` | `201`, auth response | Public |
| `POST /api/v1/auth/login` | `{ "username":"userA", "password":"<test-password>" }` | `200`, `accessToken`, `refreshToken`, `user` | Public |
| `POST /api/v1/secure/records` | `{ "content":"alpha" }` | `201`, `{ "id":1, "content":"alpha" }` | JWT |
| `GET /api/v1/secure/records/{id}` | No body | Owner `200`, other user `403`, missing ID `404` | JWT |
| `POST /api/v1/secure/records/search` | `{ "keyword":"alpha" }` | `200`, at most 50 records owned by caller | JWT |
| `POST /api/v1/vuln/records/search` | `{ "keyword":"alpha" }` | `200`; cố ý nối chuỗi, truy vấn database `sqli_lab` riêng bằng tài khoản chỉ-đọc (bật trên 2 node chính) | JWT |
| `GET /actuator/health` | No body | `200`, `{ "status":"UP" }` when healthy | Public |

Missing or invalid JWT on protected Record endpoints returns `401`. Record owner is taken from the authenticated principal; clients cannot choose it. Secure search uses JPA parameter binding. ~~Vulnerable search must remain off on the main backend.~~ Cập nhật: cụm `/vuln` bật trên 2 node chính để đối chứng theo đề cương; phần SQLi chỉ chạm database `sqli_lab` (xem mục cuối).

~~V2: lab identities and JWT key are separate from the main backend.~~ Cập nhật: không còn lab riêng; `/vuln` và `/secure` dùng chung token, JWT secret và CSDL. `X-Request-ID` accepts 1–64 ASCII letters/digits/dot/underscore/hyphen, starting with a letter/digit; other inputs are replaced with a UUID. Nginx luôn tự sinh mã này (32 ký tự hex).

Detailed standalone request/response and WAF notes: `backend/docs/BACKEND_HANDOVER.md` and `backend/docs/WAF_INTEGRATION.md` (tài liệu lịch sử của TV3, xem ghi chú cập nhật ở đầu mỗi file).

## Final-hardening response/query notes — TV4

- Post and Comment `author` objects (including nested replies and write responses) contain `id`, `username`, `role`; **`author.email` is removed**. Auth register/login `user.email` remains the caller's own email. No endpoint or request-body field is added/renamed.
- `GET /api/v1/posts` accepts sort properties `id`, `title`, `createdAt`, `updatedAt`, with optional `asc`/`desc`; default `createdAt,desc` unchanged. Unknown/nested properties (including `author.password`), malformed directions and invalid pagination return 400 using the existing error response shape. Page is nonnegative, size is positive, cap remains 50.
- `GET /api/v1/posts/me` returns every owned status, including DRAFT/ARCHIVED; no other owner's Posts. The read-policy 403 message uses `read`, not `modify`.
- Protected routes retain anonymous/invalid-JWT 401 and authenticated-insufficient-permission 403, with backend Request ID/access logging. Public endpoints remain unchanged. These are backend responses, not WAF evidence. **Cập nhật:** đọc bài DRAFT/ARCHIVED (và bình luận của bài đó) khi **chưa đăng nhập** trả `401` (trước đây `403`), đúng mục 6 đề cương; đã đăng nhập nhưng không phải chủ sở hữu/ADMIN vẫn `403`.
- JWT key variables retain their names and Base64 contract; startup now requires at least 32 decoded bytes with no raw-key fallback. ~~Backend audit uses the direct peer IP; forwarded IP headers are not trusted.~~ Cập nhật: mặc định vẫn không tin proxy nào; profile `integration` chỉ tin `X-Forwarded-For` từ đúng IP của `nginx-waf` (xem mục cuối).

Kết quả gốc của TV3: 152 Maven / 42 HTTP secure-lab / 12 two-node PASS. Details and limits: [Feature Freeze hardening](../../backend/docs/FEATURE_FREEZE.md).

## Tích hợp nhóm qua Nginx + WAF

Truy cập qua `https://localhost` (Nginx + ModSecurity); backend không publish cổng ra host. Cụm `/vuln` và
`/secure` chạy trên cùng 2 node backend, dùng chung token lấy ở `POST /api/v1/auth/login`.

**Cặp đối chứng bài viết** (`SecurePostController` và `VulnerablePostController`; cụm `/vuln` chỉ hoạt động
khi profile `sqli-lab` và `SQLI_DEMO_ENABLED=true`, đã bật trên 2 node):

| Method and path | Bản vá `/secure` | Bản lỗi `/vuln` |
|---|---|---|
| `GET /api/v1/{secure|vuln}/posts/{id}` | chưa đăng nhập `401`; nháp của người khác `403`; author không có email | **không cần đăng nhập**, đọc mọi trạng thái, trả `author.email` (tái hiện lỗi gốc "đọc công khai") |
| `PUT /api/v1/{secure|vuln}/posts/{id}` | chưa đăng nhập `401`; người khác `403` | cần đăng nhập, không kiểm tra chủ sở hữu (IDOR) |
| `DELETE /api/v1/{secure|vuln}/posts/{id}` | chưa đăng nhập `401`; người khác `403` | cần đăng nhập, không kiểm tra chủ sở hữu (IDOR) |

**SQLi Record**: `POST /api/v1/vuln/records/search` nối chuỗi `keyword`, truy vấn database `sqli_lab`
(tài khoản chỉ-đọc, chỉ 3 dòng giả). PostgreSQL không cho truy vấn chéo database nên UNION sang `blogdb`
thất bại (`400`). Bản vá `POST /api/v1/secure/records/search` bind tham số, chỉ trả Record của người gọi.

**IP trong audit log**: profile `integration` bật `server.forward-headers-strategy: native` và chỉ tin
`X-Forwarded-For` khi kết nối đến từ IP khớp `TRUSTED_PROXY_REGEX` (IP cố định của `nginx-waf`). `ip=` trong
log backend vì vậy là IP client thật khi đi qua Nginx.

**Phân biệt 403**: WAF chặn trả `{"status":403,"message":"Request blocked by WAF","requestId":...}` kèm header
`X-Blocked-By: waf`; 403 phân quyền của backend không có header này.

**Không công khai qua Nginx**: `/actuator/*` (trừ `/actuator/health`), `/swagger-ui*`, `/v3/api-docs*` trả `404`.
