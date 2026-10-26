package com.blogapi.demo;

import com.blogapi.dto.response.RecordResponse;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.condition.EnabledIfEnvironmentVariable;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.time.Duration;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.junit.jupiter.api.Assertions.assertTimeoutPreemptively;

/** Run explicitly against the separate disposable PostgreSQL lab, never against the business DB. */
@EnabledIfEnvironmentVariable(named = "SQLI_LAB_TEST_ENABLED", matches = "true")
class SqliLabPostgresTest {

    private SqliLabRepository repository;
    private SqliLabProperties properties;

    @BeforeEach
    void connectToExplicitLab() {
        properties = new SqliLabProperties(System.getenv("SQLI_DEMO_DB_URL"),
                System.getenv("SQLI_DEMO_DB_USERNAME"), System.getenv("SQLI_DEMO_DB_PASSWORD"));
        repository = new SqliLabRepository(properties, "jdbc:postgresql://postgres:5432/blogdb");
        repository.verifyAtStartup();
    }

    @Test
    void normalQueryMatchesOneFixtureButInjectionChangesLabQueryLogic() {
        assertThat(repository.search("alpha"))
                .containsExactly(new RecordResponse(1L, "LAB-ONLY alpha report"));
        assertThat(repository.search("' OR 1=1 -- "))
                .containsExactly(new RecordResponse(1L, "LAB-ONLY alpha report"),
                        new RecordResponse(2L, "LAB-ONLY beta note"),
                        new RecordResponse(3L, "LAB-ONLY gamma archive"));
    }

    @Test
    void injectionCannotReadBusinessTablesOrPostgresCredentialCatalog() {
        for (String table : List.of("public.users", "public.refresh_tokens", "public.secure_records")) {
            assertThatThrownBy(() -> repository.search("' UNION SELECT id, 'blocked' FROM " + table + " -- "))
                    .isInstanceOf(SqliLabRepository.LabQueryException.class)
                    .hasMessage("Demo query rejected").hasNoCause();
        }
        assertThatThrownBy(() -> repository.search("' UNION SELECT oid::bigint, rolpassword FROM pg_catalog.pg_authid -- "))
                .isInstanceOf(SqliLabRepository.LabQueryException.class).hasNoCause();
    }

    @Test
    void stackedStatementCannotAlterTheReaderAccount() {
        assertThatThrownBy(() -> repository.search("'; ALTER ROLE sqli_demo_reader NOLOGIN; -- "))
                .isInstanceOf(SqliLabRepository.LabQueryException.class).hasMessage("Demo query rejected");
        assertThat(repository.search("alpha")).hasSize(1);
    }

    @Test
    void readerHasOnlySelectOnDemoAndNoWritePrivilegesOrRoleEscalation() throws Exception {
        try (Connection connection = DriverManager.getConnection(properties.jdbcUrl(), properties.username(), properties.password());
             Statement statement = connection.createStatement()) {
            try (ResultSet row = statement.executeQuery("""
                    SELECT current_setting('default_transaction_read_only') AS ro,
                      has_table_privilege(current_user, 'demo.records', 'SELECT') AS can_read,
                      has_table_privilege(current_user, 'demo.records', 'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER') AS can_write,
                      has_database_privilege(current_user, current_database(), 'CREATE,TEMP') AS can_create,
                      (SELECT count(*) FROM pg_auth_members WHERE member = (SELECT oid FROM pg_roles WHERE rolname=current_user)) AS memberships
                    """)) {
                assertThat(row.next()).isTrue();
                assertThat(row.getString("ro")).isEqualTo("on");
                assertThat(row.getBoolean("can_read")).isTrue();
                assertThat(row.getBoolean("can_write")).isFalse();
                assertThat(row.getBoolean("can_create")).isFalse();
                assertThat(row.getInt("memberships")).isZero();
            }
            // A failed write is attempted only inside the disposable fixture DB; ACLs still apply
            // even if a malicious SQL statement changes its own transaction-read-only setting.
            statement.execute("SET default_transaction_read_only = off");
            assertThatThrownBy(() -> statement.executeUpdate("INSERT INTO demo.records VALUES (99, 'must-not-be-written')"))
                    .isInstanceOf(SQLException.class);
        }
        assertThat(repository.search("LAB-ONLY")).hasSize(3);
    }

    @Test
    void expensiveInjectedQueryIsCancelledWithoutLeakingSql() {
        assertTimeoutPreemptively(Duration.ofSeconds(8), () ->
                assertThatThrownBy(() -> repository.search("no-match' OR EXISTS (SELECT 1 FROM pg_sleep(5)) -- "))
                        .isInstanceOf(SqliLabRepository.LabQueryException.class)
                        .hasMessage("Demo query rejected").hasNoCause());
    }
}
