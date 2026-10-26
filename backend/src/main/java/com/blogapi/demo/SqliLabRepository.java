package com.blogapi.demo;

import com.blogapi.dto.response.RecordResponse;

import java.net.URI;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.util.ArrayList;
import java.util.List;
import java.util.Properties;

/** An intentionally unsafe query, exclusively against the separate, disposable lab database. */
public final class SqliLabRepository {

    private static final String READER = "sqli_demo_reader";
    private static final List<RecordResponse> FIXTURES = List.of(
            new RecordResponse(1L, "LAB-ONLY alpha report"),
            new RecordResponse(2L, "LAB-ONLY beta note"),
            new RecordResponse(3L, "LAB-ONLY gamma archive"));

    private final SqliLabProperties properties;

    public SqliLabRepository(SqliLabProperties properties, String businessJdbcUrl) {
        validateConfiguration(properties, businessJdbcUrl);
        this.properties = properties;
    }

    public void verifyAtStartup() {
        try (Connection connection = openConnection()) {
            try {
                verifyIsolation(connection);
            } catch (SQLException ex) {
                throw new LabUnavailableException();
            }
        } catch (SQLException | LabUnavailableException ex) {
            // Do not attach driver exceptions: they can contain connection details or SQL text.
            throw new IllegalStateException("SQLi lab isolation check failed; lab API will not start");
        }
    }

    public List<RecordResponse> search(String keyword) {
        // Containment only: forbid stacked statements that could alter the lab role itself.
        // Boolean/UNION SQL injection remains deliberately possible against fake fixtures.
        if (keyword.indexOf(';') >= 0) throw new LabQueryException();
        try (Connection connection = openConnection()) {
            // Recheck permissions and fixture-only contents on every connection, before accepting input.
            try {
                verifyIsolation(connection);
            } catch (SQLException ex) {
                throw new LabUnavailableException();
            }
            try (Statement statement = connection.createStatement()) {
                statement.setQueryTimeout(2);
                statement.setMaxRows(50);
                // Deliberate lab vulnerability. Never reuse this code with a business datasource.
                String sql = "SELECT id, content FROM demo.records WHERE content LIKE '%" + keyword
                        + "%' ORDER BY id LIMIT 50";
                List<RecordResponse> records = new ArrayList<>();
                try (ResultSet rows = statement.executeQuery(sql)) {
                    while (rows.next() && records.size() < 50) {
                        records.add(new RecordResponse(rows.getLong("id"), rows.getString("content")));
                    }
                }
                connection.rollback();
                return records;
            } catch (SQLException ex) {
                throw new LabQueryException();
            }
        } catch (SQLException ex) {
            throw new LabUnavailableException();
        }
    }

    private Connection openConnection() throws SQLException {
        Properties credentials = new Properties();
        credentials.setProperty("user", properties.username());
        credentials.setProperty("password", properties.password());
        credentials.setProperty("connectTimeout", "5");
        credentials.setProperty("socketTimeout", "5");
        Connection connection = DriverManager.getConnection(properties.jdbcUrl(), credentials);
        try {
            connection.setReadOnly(true);
            connection.setAutoCommit(false);
            return connection;
        } catch (SQLException ex) {
            connection.close();
            throw ex;
        }
    }

    static void validateConfiguration(SqliLabProperties properties, String businessJdbcUrl) {
        try {
            if (properties == null || properties.jdbcUrl() == null
                    || !properties.jdbcUrl().startsWith("jdbc:postgresql://")
                    || !READER.equals(properties.username())
                    || properties.password() == null || properties.password().isBlank()) {
                throw new IllegalArgumentException();
            }
            URI url = URI.create(properties.jdbcUrl().substring("jdbc:".length()));
            if (url.getHost() == null || !"/sqli_lab".equals(url.getPath())
                    || url.getUserInfo() != null || url.getQuery() != null || url.getFragment() != null
                    || properties.jdbcUrl().equals(businessJdbcUrl)
                    || (businessJdbcUrl != null && URI.create(businessJdbcUrl.substring("jdbc:".length()))
                    .getPath().equals("/sqli_lab"))) {
                throw new IllegalArgumentException();
            }
        } catch (RuntimeException ex) {
            throw new IllegalArgumentException("SQLi lab requires its own PostgreSQL database and restricted reader");
        }
    }

    private void verifyIsolation(Connection connection) throws SQLException {
        if (!"PostgreSQL".equals(connection.getMetaData().getDatabaseProductName())) rejectIsolation();
        try (Statement statement = connection.createStatement()) {
            statement.setQueryTimeout(2);
            try (ResultSet row = statement.executeQuery("""
                    SELECT current_database() AS db, current_user AS usr,
                           current_setting('default_transaction_read_only') AS read_only,
                           r.rolsuper, r.rolcreatedb, r.rolcreaterole, r.rolreplication, r.rolbypassrls,
                           r.rolinherit,
                           EXISTS (SELECT 1 FROM pg_auth_members m WHERE m.member = r.oid) AS memberships,
                           has_database_privilege(current_user, current_database(), 'CREATE,TEMP') AS db_write
                    FROM pg_roles r WHERE r.rolname = current_user
                    """)) {
                if (!row.next() || !"sqli_lab".equals(row.getString("db"))
                        || !READER.equals(row.getString("usr")) || !"on".equals(row.getString("read_only"))
                        || row.getBoolean("rolsuper") || row.getBoolean("rolcreatedb")
                        || row.getBoolean("rolcreaterole") || row.getBoolean("rolreplication")
                        || row.getBoolean("rolbypassrls") || row.getBoolean("rolinherit")
                        || row.getBoolean("memberships") || row.getBoolean("db_write")) rejectIsolation();
            }
            try (ResultSet row = statement.executeQuery("""
                    SELECT EXISTS (SELECT 1 FROM pg_namespace n
                                   WHERE left(n.nspname, 3) <> 'pg_' AND n.nspname <> 'information_schema'
                                   AND has_schema_privilege(current_user, n.oid, 'CREATE')) AS schema_write,
                           EXISTS (SELECT 1 FROM pg_extension WHERE extname <> 'plpgsql') AS extra_extensions,
                           EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                                   WHERE left(n.nspname, 3) <> 'pg_' AND n.nspname <> 'information_schema') AS extra_functions,
                           EXISTS (SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                                   WHERE c.relkind = 'S' AND left(n.nspname, 3) <> 'pg_'
                                   AND n.nspname <> 'information_schema') AS extra_sequences
                    """)) {
                if (!row.next() || row.getBoolean("schema_write") || row.getBoolean("extra_extensions")
                        || row.getBoolean("extra_functions") || row.getBoolean("extra_sequences")) rejectIsolation();
            }
            try (ResultSet rows = statement.executeQuery("""
                    SELECT n.nspname, c.relname,
                           has_table_privilege(current_user, c.oid, 'SELECT') AS can_read,
                           has_table_privilege(current_user, c.oid, 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') AS can_write,
                           has_any_column_privilege(current_user, c.oid, 'INSERT,UPDATE,REFERENCES') AS column_write
                    FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
                    WHERE left(n.nspname, 3) <> 'pg_' AND n.nspname <> 'information_schema'
                          AND c.relkind IN ('r', 'p', 'v', 'm', 'f')
                    """)) {
                if (!rows.next() || !"demo".equals(rows.getString("nspname"))
                        || !"records".equals(rows.getString("relname")) || !rows.getBoolean("can_read")
                        || rows.getBoolean("can_write") || rows.getBoolean("column_write") || rows.next()) rejectIsolation();
            }
            List<RecordResponse> actual = new ArrayList<>();
            try (ResultSet rows = statement.executeQuery("SELECT id, content FROM demo.records ORDER BY id LIMIT 4")) {
                while (rows.next()) actual.add(new RecordResponse(rows.getLong(1), rows.getString(2)));
            }
            if (!FIXTURES.equals(actual)) rejectIsolation();
        }
    }

    private static void rejectIsolation() { throw new LabUnavailableException(); }

    public static final class LabQueryException extends RuntimeException {
        public LabQueryException() { super("Demo query rejected"); }
    }

    public static final class LabUnavailableException extends RuntimeException {
        public LabUnavailableException() { super("SQLi lab isolation check failed"); }
    }
}
