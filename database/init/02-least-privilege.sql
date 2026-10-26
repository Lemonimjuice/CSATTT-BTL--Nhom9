\set ON_ERROR_STOP on
-- psql script for a NEW database; credentials come from process environment.
-- APP_DB_USERNAME defaults to app_user; APP_DB_PASSWORD is required.
\getenv app_role APP_DB_USERNAME
\if :{?app_role}
\else
    \set app_role app_user
\endif
\getenv app_password APP_DB_PASSWORD
\if :{?app_password}
\else
    \echo 'APP_DB_PASSWORD is required; no role was created.'
    \quit 1
\endif
SELECT length(:'app_password') >= 24 AS password_valid \gset
\if :password_valid
\else
    \echo 'Use a randomly generated APP_DB_PASSWORD of at least 24 characters.'
    \quit 1
\endif
SELECT current_database() AS app_database \gset
BEGIN;
CREATE ROLE :"app_role" LOGIN PASSWORD :'app_password'
    NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
REVOKE ALL ON DATABASE :"app_database" FROM PUBLIC;
GRANT CONNECT ON DATABASE :"app_database" TO :"app_role";
REVOKE ALL ON SCHEMA public FROM PUBLIC;
GRANT USAGE ON SCHEMA public TO :"app_role";
-- Exactly the operations used by the current APIs; schema stays admin-owned.
GRANT SELECT, INSERT ON public.users, public.secure_records TO :"app_role";
GRANT SELECT, INSERT, DELETE ON public.refresh_tokens TO :"app_role";
GRANT SELECT, INSERT, UPDATE, DELETE ON public.posts, public.comments, public.categories TO :"app_role";
GRANT USAGE ON SEQUENCE public.users_id_seq, public.secure_records_id_seq,
    public.refresh_tokens_id_seq, public.posts_id_seq, public.comments_id_seq,
    public.categories_id_seq TO :"app_role";
ALTER ROLE :"app_role" IN DATABASE :"app_database" SET search_path = public;
COMMIT;
