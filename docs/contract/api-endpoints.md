# TV3 API contract

Container port: 8080. JSON requests use `Content-Type: application/json`. Protected requests use `Authorization: Bearer <accessToken>`.

| Method and path | Request | Expected response | Auth |
|---|---|---|---|
| `POST /api/v1/auth/register` | `{ "username":"userA", "email":"userA@example.test", "password":"<test-password>" }` | `201`, auth response | Public |
| `POST /api/v1/auth/login` | `{ "username":"userA", "password":"<test-password>" }` | `200`, `accessToken`, `refreshToken`, `user` | Public |
| `POST /api/v1/secure/records` | `{ "content":"alpha" }` | `201`, `{ "id":1, "content":"alpha" }` | JWT |
| `GET /api/v1/secure/records/{id}` | No body | Owner `200`, other user `403`, missing ID `404` | JWT |
| `POST /api/v1/secure/records/search` | `{ "keyword":"alpha" }` | `200`, at most 50 records owned by caller | JWT |
| `POST /api/v1/vuln/records/search` | `{ "keyword":"alpha" }` | Main backend `404` when disabled; isolated lab only when enabled | JWT + lab flag/profile |
| `GET /actuator/health` | No body | `200`, `{ "status":"UP" }` when healthy | Public |

Missing or invalid JWT on protected Record endpoints returns `401`. Record owner is taken from the authenticated principal; clients cannot choose it. Secure search uses JPA parameter binding. Vulnerable search must remain off on the main backend.

V2: lab identities and JWT key are separate from the main backend. Register/login at the lab URL to obtain a lab token; main/lab JWTs must return `401` when used across these two environments. This differs from the two **main** nodes, which must share the same JWT secret. `X-Request-ID` accepts 1–64 ASCII letters/digits/dot/underscore/hyphen, starting with a letter/digit; other inputs are replaced with a UUID. See [current V2 handover](tv3-v2-handover.md) for configuration, evidence and TV1/TV2 responsibilities.

Detailed standalone request/response and WAF notes: `backend/docs/BACKEND_HANDOVER.md` and `backend/docs/WAF_INTEGRATION.md`. Group Nginx/WAF behavior has not been tested with these files.

## Final-hardening response/query notes — TV4

- Post and Comment `author` objects (including nested replies and write responses) contain `id`, `username`, `role`; **`author.email` is removed**. Auth register/login `user.email` remains the caller's own email. No endpoint or request-body field is added/renamed.
- `GET /api/v1/posts` accepts sort properties `id`, `title`, `createdAt`, `updatedAt`, with optional `asc`/`desc`; default `createdAt,desc` unchanged. Unknown/nested properties (including `author.password`), malformed directions and invalid pagination return 400 using the existing error response shape. Page is nonnegative, size is positive, cap remains 50.
- `GET /api/v1/posts/me` returns every owned status, including DRAFT/ARCHIVED; no other owner's Posts. The read-policy 403 message uses `read`, not `modify`.
- Protected routes retain anonymous/invalid-JWT 401 and authenticated-insufficient-permission 403, with backend Request ID/access logging. Public endpoints and private Post visibility rules remain unchanged. These are backend responses, not WAF evidence.
- JWT key variables retain their names and Base64 contract; startup now requires at least 32 decoded bytes with no raw-key fallback. Backend audit uses the direct peer IP; forwarded IP headers are not trusted.

Latest verified result: 152 Maven / 42 HTTP secure-lab / 12 two-node PASS, 0 Maven failures/errors/skips. Details and limits: [Feature Freeze hardening](../../backend/docs/FEATURE_FREEZE.md).
