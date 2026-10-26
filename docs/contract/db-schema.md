# TV3 database schema and privileges

Authoritative fresh-database scripts: `database/init/01-schema.sql` followed by `database/init/02-least-privilege.sql`. They create six tables matching the current JPA entities:

| Table | Main columns and relationships |
|---|---|
| `users` | `id` bigint identity; unique `username`/`email`; password hash, role, enabled, timestamps |
| `categories` | `id` bigint identity; name, unique slug, description, timestamps |
| `posts` | `id` bigint identity; title, unique slug, content, summary, status, `author_id -> users`, optional `category_id -> categories`, timestamps |
| `comments` | `id` bigint identity; content, `post_id -> posts`, `author_id -> users`, optional `parent_id -> comments`, depth, deleted, timestamps |
| `refresh_tokens` | `id` bigint identity; unique token, unique `user_id -> users`, expiration |
| `secure_records` | `id` bigint identity; content, `owner_id -> users` |

The final group-repository Docker E2E run on 2026-10-27 applied both scripts to fresh temporary PostgreSQL 16. Both backend nodes started with profile `integration` and `ddl-auto=validate`, using the generated application role; cross-node Record create/read and ownership tests passed. The separate SQLi lab's PostgreSQL fixture/privilege tests also passed as part of the 39-test Maven suite, with no failures/errors/skips. These are disposable-database results, not evidence that the existing business volume was migrated. See [V2 handover](tv3-v2-handover.md).

`02-least-privilege.sql` reads `APP_DB_USERNAME` and `APP_DB_PASSWORD` from the PostgreSQL process environment. It creates a non-admin login role, grants CONNECT and schema USAGE, scoped table DML and identity-sequence USAGE. It does not grant schema creation or ownership. The Backend uses `DB_USERNAME` and `DB_PASSWORD` for that same role.

These scripts are for a **new** database. Do not apply them to the existing business volume: `01-schema.sql` has no migration logic and `02-least-privilege.sql` creates a role. TV1 must decide how to provision a fresh group database, set the role environment, and mount/init scripts. TV4 owns seed data (`03-seed-data.sql`); no seed data is included here.
