#!/bin/sh
set -eu
# Tạo database riêng "sqli_lab" trong CÙNG container PostgreSQL với blogdb, cùng một tài khoản
# chỉ-đọc "sqli_demo_reader". Dùng cho cụm API lỗi /api/v1/vuln (Demo 2, 3).
#
# Vì sao vẫn an toàn dù cố ý để lỗ hổng SQLi: PostgreSQL không cho một câu lệnh SELECT
# truy vấn chéo sang database khác. Reader chỉ CONNECT được vào sqli_lab, chỉ SELECT bảng
# demo.records, và bị đặt read-only. Nên dù bị ' OR 1=1 hay UNION, kẻ tấn công vẫn không
# chạm được bảng public.users của blogdb.
: "${SQLI_LAB_READER_PASSWORD:?SQLI_LAB_READER_PASSWORD is required}"

# Chạy ngoài transaction: CREATE DATABASE không nằm trong khối BEGIN được.
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -c "CREATE DATABASE sqli_lab"

psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname sqli_lab \
  --set=reader_password="$SQLI_LAB_READER_PASSWORD" <<'SQL'
CREATE ROLE sqli_demo_reader LOGIN PASSWORD :'reader_password'
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOINHERIT NOREPLICATION NOBYPASSRLS;
REVOKE ALL ON DATABASE sqli_lab FROM PUBLIC;
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
