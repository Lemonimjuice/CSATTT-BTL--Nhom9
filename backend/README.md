# TV3 Backend Security handover

Spring Boot Blog API (DevFinesse base), Java 21 / Spring Boot 3.2.5 / Maven. Build context is this `backend/` directory: `docker build -f backend/Dockerfile backend` from the group root.

## Scope and verified status

- Code includes JWT/BCrypt authentication, Record create/read/search with ownership, and an opt-in SQLi comparison lab. The normal backend keeps the vulnerable endpoint disabled.
- The source backend previously reported 27 Maven tests and 26 HTTP E2E cases passing; these were not rerun during this copy.
- TV3's temporary PostgreSQL 16 check of `database/init/01-schema.sql` and `02-least-privilege.sql` passed, including six tables and application privileges. Hibernate startup with profile `integration` and `ddl-auto=validate` also passed on a temporary PostgreSQL 16 instance, as reported by the operator.
- `scripts/Test-TwoNodeIntegration.ps1` is prepared and PowerShell syntax checked, but **has not been executed**. JWT cross-instance, shared Record, ownership across nodes, and node-stop readiness are not yet runtime verified in the group repository.
- The group Compose, Nginx, ModSecurity, WAF routing, and SQLi lab integration are not yet verified with this backend.

## Group integration contract

- TV1 owns root `docker-compose.yml` and `nginx/`; both still use HTTP Echo nodes. Replace those nodes with the same image built from `backend/`, expose container port 8080 internally, and use the same `JWT_SECRET`, `DB_HOST=database`, `DB_PORT=5432`, `DB_NAME=blogdb`, `DB_USERNAME`, and `DB_PASSWORD` on both nodes.
- Use `SPRING_PROFILES_ACTIVE=integration`. Its Hibernate mode is `validate`; schema must exist before either node starts. The application DB role needs the rights granted by `database/init/02-least-privilege.sql` and must not own the schema.
- On a **fresh disposable database only**, apply `database/init/01-schema.sql` then `02-least-privilege.sql` with `APP_DB_USERNAME` and `APP_DB_PASSWORD`. Do not run these scripts on the current business volume or use `docker compose down -v`.
- The root Compose does not yet mount these scripts or supply the application role/environment. TV1 must integrate these values without placing real credentials in Git. Its current `DB_ADMIN_PASSWORD` fallback should be removed before a shared demo.
- `.env.example` and `.env.sqli-lab.example` here contain placeholders only. They are examples for the older standalone backend setup, not a replacement for TV1's root `.env.example`.

## SQLi lab boundary

`docker-compose.sqli-lab.yml` and `docker/sqli-lab/init-demo.sh` are retained as **standalone reference assets**. The overlay names old services `postgres` and `blog-net`, so it must not be applied to the group's root Compose unchanged. TV1/TV2 must route a separate lab container/database and preserve the lab reader's SELECT-only rights and default-off flag. The lab API's primary datasource still uses business DB authentication; do not describe it as fully independent of business identity data.

## Documents and scripts

- `docs/BACKEND_HANDOVER.md` and `docs/WAF_INTEGRATION.md` preserve prior standalone contracts and evidence. Their old Compose commands are not group deployment instructions.
- `scripts/Test-DatabaseInit.ps1` and `scripts/Test-HibernateValidation.ps1` target `../database/init/` and create disposable resources; the latter is copied from the operator's fixed script.
- `scripts/Test-TwoNodeIntegration.ps1` targets `../database/init/`; it builds a test image, starts two localhost-bound backends and a non-published temporary PostgreSQL, then cleans up owned resources. Run it separately before claiming the two-node demo works.
- `scripts/Test-SqliE2E.ps1` checks HTTP contracts against explicit local URLs. `scripts/Test-BackendTests.ps1` can run default Maven tests; its `-WithLab` mode still assumes the standalone Compose and must be adapted before group use.
- Endpoint summary: `../docs/contract/api-endpoints.md`; schema/privileges: `../docs/contract/db-schema.md`.
