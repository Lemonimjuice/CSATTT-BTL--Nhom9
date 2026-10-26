#!/bin/sh
set -eu

# Executed only in the separate disposable lab PostgreSQL container.
[ "$POSTGRES_DB" = "sqli_lab" ] && [ "$POSTGRES_USER" = "sqli_lab_admin" ]
: "${SQLI_LAB_READER_PASSWORD:?SQLI_LAB_READER_PASSWORD is required}"

psql --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" \
  --set=ON_ERROR_STOP=1 --set=reader_password="$SQLI_LAB_READER_PASSWORD" <<'SQL'
CREATE ROLE sqli_demo_reader LOGIN PASSWORD :'reader_password'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
REVOKE ALL ON DATABASE sqli_lab FROM PUBLIC;
REVOKE ALL ON DATABASE postgres FROM PUBLIC;
REVOKE ALL ON DATABASE template1 FROM PUBLIC;
GRANT CONNECT ON DATABASE sqli_lab TO sqli_demo_reader;
REVOKE ALL ON SCHEMA public FROM PUBLIC;

CREATE SCHEMA demo;
CREATE TABLE demo.records (id bigint PRIMARY KEY, content text NOT NULL);
INSERT INTO demo.records (id, content) VALUES
  (1, 'LAB-ONLY alpha report'),
  (2, 'LAB-ONLY beta note'),
  (3, 'LAB-ONLY gamma archive');
GRANT USAGE ON SCHEMA demo TO sqli_demo_reader;
GRANT SELECT ON demo.records TO sqli_demo_reader;

ALTER ROLE sqli_demo_reader IN DATABASE sqli_lab SET default_transaction_read_only = on;
ALTER ROLE sqli_demo_reader IN DATABASE sqli_lab SET statement_timeout = '2s';
ALTER ROLE sqli_demo_reader IN DATABASE sqli_lab SET lock_timeout = '500ms';
SQL
