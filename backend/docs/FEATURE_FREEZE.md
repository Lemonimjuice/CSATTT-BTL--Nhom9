# Backend V2 final hardening — 2026-10-27

> **Ghi chú tích hợp nhóm (27/10/2026), đọc trước:** đây là tài liệu lịch sử của TV3, viết khi cụm `/vuln` còn chạy trong lab riêng. Thiết kế nhóm hiện tại khác ở 4 điểm: (1) cụm `/vuln` bật trên 2 node chính (`SQLI_DEMO_ENABLED=true`), phần SQLi chỉ truy vấn database `sqli_lab` riêng bằng tài khoản chỉ-đọc; (2) không còn lab, identity DB hay JWT riêng, `/vuln` và `/secure` dùng chung token; (3) profile `integration` chỉ tin `X-Forwarded-For` từ IP của `nginx-waf`, nên audit ghi IP client thật; (4) chưa đăng nhập mà đọc bài riêng tư trả `401`. Nginx/WAF đã tích hợp và kiểm chứng. Chi tiết: [docs/decisions.md](../../docs/decisions.md).

Branch: `feat/tv3-backend`. Baseline: `101d4c6`. Scope: the six requested P1 checks, their regressions and two small P2 fixes. No root Compose/Nginx/ModSecurity change, new endpoint, schema change, audit table or new environment variable.

## Findings and disposition

| Item | Before-fix evidence | Final behavior |
|---|---|---|
| P1.1 sorting | `author.password` was accepted; unknown properties reached JPA/error handling; malformed sort/pagination was not rejected consistently | Controller allowlist: `id`, `title`, `createdAt`, `updatedAt`; direction `asc`/`desc`; invalid property/direction/page/size returns 400 before querying the repository |
| P1.2 public email | All eight tested public Post/Comment read routes exposed email through the shared author DTO | Separate `PublicUserSummary` omits email from Post/Comment authors and nested replies. Register/login keep the caller's own `user.email` |
| P1.3 401/403 | The protected-endpoint matrix already passed on baseline, using the real Spring Security chain | Existing authorization configuration retained. Anonymous/invalid JWT is 401 on protected routes; authenticated unauthorized writes are 403. Public reads and the prior private-Post visibility policy remain intact |
| P1.4 audit | No correlated failed-login event with username/IP; no access-event peer IP; raw login username and exception text could enter logs | Success/failure auth events, bounded sanitized display username, Request ID correlation and direct peer IP. Audit/access events do not include passwords, JWT, refresh tokens, request bodies or raw exception text |
| P1.5 JWT config | Invalid/short keys were accepted during startup; signing-key method contained a raw-byte fallback | Startup validates basic Base64 and at least 32 decoded bytes, with no raw fallback. Valid padded/unpadded Base64 stays supported. Errors do not echo the secret or decoder exception |
| P1.6 exceptions | Escaped servlet/IO exceptions skipped the access event | One access event in `finally`, MDC cleanup in a nested `finally`; an uncommitted escaped exception gets status 500, while an already committed status is retained. Error redispatch does not create duplicate access events |
| P2 own posts | `/posts/me` queried all posts unnecessarily and returned only PUBLISHED | One owner-filtered paginated repository query returns all own statuses, including DRAFT/ARCHIVED; no unused `findAll` |
| P2 read message | Non-owner read denial said `modify` | Read-policy 403 message now says `read`; write-denial messages are unchanged |

Before fixes, the final 60-test regression set produced **37 failures, 0 errors, 0 skipped** against baseline. The test-only exception controller is explicitly imported and profile-restricted; its fixture routes are not production endpoints. The old 92 tests were not removed, disabled or weakened.

## Verification on patched source

| Check | Actual result |
|---|---|
| New `FinalHardeningApiIntegrationTest` | 38/38 PASS: sorting, public email, self email, protected writes, own-post query and read message; Spring Boot/MockMvc + real security chain + H2 |
| New `FinalAuditIntegrationTest` | 9/9 PASS: real embedded Tomcat HTTP, login success/failure, username injection, forged forwarded IP headers, 401/403, handled/escaped exception, one event and MDC cleanup |
| New `JwtSecretStartupTest` | 11/11 PASS: startup/signing with 32/48/64-byte test keys, padded/unpadded forms; malformed/null/empty/short keys fail closed |
| New `MdcExceptionLifecycleTest` | 2/2 PASS: escaped exception log and cleanup, including an already committed 202 response |
| Entire local Maven suite | 152 total: 147 PASS, 0 failures/errors, 5 PostgreSQL skipped (no opt-in in this run) |
| Entire Docker Maven suite | **152 PASS, 0 failures/errors/skipped**, including all 92 old tests and the real PostgreSQL lab tests |
| Real PostgreSQL HTTP suite | **42/42 PASS**: all 30 old cases retained plus 12 Post/contract checks; self-email assertion strengthened |
| Two-node HTTP | **12/12 PASS**, both startup health checks UP; same image/DB/JWT, Record cross-node, IDOR 403, Node2 after stopping Node1 |
| Isolation / port binding / cleanup | PASS; no business resources modified |

Full Docker host runner exited 0 on Engine 29.9.2 / Compose v5.6.1. Disposable project: `tv3v2383278890cc0`; node run: `98fdd0b5a7de421cac4688ecdbadcd21`. Runtime logs remain local in ignored `backend/logs/`, not in Git. Reproduce from the repository root with PowerShell 7 and Docker Desktop Linux Engine:

```powershell
pwsh -NoProfile -File ./backend/scripts/Test-V2Host.ps1
```

## Contract notes for TV1 / TV4

- **TV4 response schema:** `author` in every Post/Comment response (lists, detail, nested replies and write responses) is now `{id, username, role}`; `author.email` is removed, not set to null. Soft-deleted comment author behavior is unchanged. Update Postman/schema assertions. Auth `user.email` in register/login remains available for that user.
- **TV4 query/error checks:** default sort stays `createdAt,desc`; only the four properties above and `asc`/`desc` are accepted. Invalid options return the existing JSON error shape with status 400. `page >= 0`, `size >= 1`, existing maximum page size 50 unchanged. `/posts/me` totals/content include all own statuses. Read denial now says `read`.
- **TV1 JWT configuration:** variable names, token claims, expiry and endpoints are unchanged. `JWT_SECRET` and the separate lab key must be Base64 encoding at least 32 decoded bytes; 32 text characters are not necessarily 32 key bytes. Random generation in the existing test runner and both shared main-node/separate-lab configurations passed startup and HTTP tests. Invalid legacy configuration now stops startup instead of failing later; no real `.env` was read or changed to make tests pass.
- **TV1 audit IP:** no trusted reverse proxy has been established, so `server.forward-headers-strategy: none` is explicit. Backend logs the socket peer (`remoteAddr`), ignoring client-supplied `X-Real-IP`/`X-Forwarded-For`. Behind Nginx this is the proxy IP, not proof of the original client IP. Correlate with proxy logs using Request ID; establish proxy trust separately before changing this behavior.
- Audit usernames are bounded/sanitized display values, not authorization inputs. Diagnostic exception logs now keep type/correlation rather than raw messages/stack traces that may contain input or credentials. Test signing values are deterministic fixtures only; production keys still require secure random generation.

## Remaining limits before freeze

- No failures remain in the requested checks. This is targeted hardening, not a complete security audit. Comment update/delete keep the existing author/MODERATOR/ADMIN policy; it was not redesigned in this task.
- Nginx LB/failover through the group gateway and ModSecurity/CRS blocking/audit are still **NOT RUN**. The temporary HTTP test gateway is not a WAF, and backend 401/403 events must not be presented as WAF blocks.
- Production deployment must verify its real key format and proxy assumptions. No shared environment/production credentials were inspected or rotated. No automatic merge into `integration/v2` is part of this handover.
