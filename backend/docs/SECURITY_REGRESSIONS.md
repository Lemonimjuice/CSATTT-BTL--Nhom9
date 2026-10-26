# Comment visibility and security-denial correlation — 2026-10-27

Scope: Comment `getByPost`, `getById`, `create` (including replies), and backend Request ID/access logging before Spring Security. No schema, environment variable, HTTP endpoint, root Compose, Nginx or WAF change.

## Reproduced before changing application code

The new regression suite ran against baseline `8a11b5e`: **53 tests, 21 failures, 0 errors/skips**.

- `CommentPostAccessIntegrationTest`: 46 cases, 17 failures. Private Post reads were denied while its Comment list/single/reply endpoints returned 200, including after a PUBLISHED Post became private. Other users could also create comments/replies on a private Post.
- `SecurityRequestLoggingIntegrationTest`: 7 cases, 4 failures. The actual servlet registration ordered MDC at 1 and Spring Security at -100. Missing/invalid JWT requests stopped before MDC, so their 401 responses had no Request ID. The real role-denied HTTP path also exposed error redispatch masking the original 403 as 401.

## Fixes

`PostReadAccessPolicy` contains the existing Post visibility policy and is shared by Post reads and Comment list/single/create operations. PUBLISHED remains publicly readable. DRAFT/ARCHIVED comments can only be read by the Post owner or ADMIN; MODERATOR does not gain additional private-Post visibility. Creation still requires authentication and access to the Post; unauthenticated create remains 401, private reads without permission return 403. HTTP paths, request bodies and the existing Post error messages remain unchanged. Only internal Comment service read signatures now receive the authenticated requester.

MDC remains a single automatically registered servlet filter and is not added to the Spring Security chain. Its order is now `Ordered.HIGHEST_PRECEDENCE + 1`, ahead of security. Authenticated username is copied to a server-only request attribute after JWT validation, allowing the outer access log to retain user identity after Spring Security clears its context. The existing Request ID allowlist and MDC cleanup remain in place; JWT/password/request body are not logged.

Only servlet `DispatcherType.ERROR` is permitted through authorization to preserve the backend's original error status. Direct HTTP requests to `/error` still require authentication and have a regression test. Role-denied 403 and ownership-denied 403 remain backend responses, with no WAF marker.

## Test coverage and results

| Suite/check | Environment and coverage | Result |
|---|---|---|
| Comment regression | Spring Boot + MockMvc + real Security chain + isolated H2; 3 Post states x 5 actors x 3 operations, plus visibility transition; roots/replies and denied-create row counts | 46/46 PASS |
| Security logging regression | Embedded Tomcat on a random port + real registered servlet/Security filters + isolated H2; missing/invalid JWT, role denial, ownership denial, exactly one registration/access event, JWT warning correlation, no secret/body logging, Request ID/user isolation, protected direct `/error` | 7/7 PASS |
| Full Maven on Windows | Java 21, cached Maven dependencies, no PostgreSQL opt-in | 92 total: 87 PASS, 0 failures/errors, 5 PostgreSQL skipped |
| Full Maven in Docker | PostgreSQL lab opt-in enabled; 53 new tests and all 39 existing tests | **92 PASS, 0 failures/errors/skipped** |
| Existing HTTP secure/lab E2E | PostgreSQL-backed APIs and temporary loopback test gateway | **30/30 PASS** |
| Existing two-node E2E | Same image/DB/JWT; cross-node Record, IDOR 403, Node2 after stopping Node1 | **12/12 PASS**, both startup health checks UP |
| Network isolation / port binding / cleanup | Existing disposable runner checks | **PASS** |

The full Docker host runner exited 0 on the patched source. Project: `tv3v257ec8f817afa`; two-node run: `aeec6e4cfa834b59a7470fd3ea784f19`. Raw logs remain local in ignored `backend/logs/`; they are not included in Git.

To reproduce from the repository root with PowerShell 7 and Docker Desktop Linux Engine:

```powershell
pwsh -NoProfile -File ./backend/scripts/Test-V2Host.ps1
```

For only the new Java regressions, run `mvn -Dtest=CommentPostAccessIntegrationTest,SecurityRequestLoggingIntegrationTest test` from `backend/` with Java 21/Maven. New Comment regressions use H2, and logging tests use real HTTP/Tomcat; do not describe these as new PostgreSQL Comment HTTP cases. PostgreSQL coverage here is the existing lab and HTTP/two-node suites.

## Limits

- This patch does not change Comment update/delete's existing author/MODERATOR/ADMIN policy or re-audit other Blog APIs. It addresses the three Comment operations identified in the request; remaining P2 work is out of scope.
- Nginx load-balancer failover through the group proxy and ModSecurity/CRS blocking/audit are still NOT RUN. The plain HTTP test gateway is not a WAF; backend Request ID/403 evidence must not be substituted for WAF audit evidence.
- Passing these regressions is not a complete security audit, key rotation or production-hardening certification.
