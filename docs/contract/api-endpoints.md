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

Detailed standalone request/response and WAF notes: `backend/docs/BACKEND_HANDOVER.md` and `backend/docs/WAF_INTEGRATION.md`. Group Nginx/WAF behavior has not been tested with these files.
