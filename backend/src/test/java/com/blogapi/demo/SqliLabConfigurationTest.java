package com.blogapi.demo;

import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class SqliLabConfigurationTest {

    private final ApplicationContextRunner contextRunner = new ApplicationContextRunner()
            .withUserConfiguration(SqliLabConfiguration.class);

    @Test
    void labIsAbsentByDefaultAndRequiresBothExplicitGates() {
        contextRunner.run(context -> assertThat(context).doesNotHaveBean(SqliLabRepository.class));
        contextRunner.withPropertyValues("app.demo.sqli.enabled=true")
                .run(context -> assertThat(context).doesNotHaveBean(SqliLabRepository.class));
        contextRunner.withInitializer(context -> context.getEnvironment().setActiveProfiles("sqli-lab"))
                .run(context -> assertThat(context).doesNotHaveBean(SqliLabRepository.class));
    }

    @Test
    void enabledLabRefusesAnUnrestrictedOrBusinessDatasource() {
        String business = "jdbc:postgresql://postgres:5432/blogdb";
        assertThatThrownBy(() -> new SqliLabRepository(
                new SqliLabProperties(business, "sqli_demo_reader", "test-only-password"), business))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new SqliLabRepository(
                new SqliLabProperties("jdbc:postgresql://sqli-lab-db:5432/sqli_lab", "admin", "test-only-password"), business))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new SqliLabRepository(
                new SqliLabProperties("jdbc:postgresql://sqli-lab-db:5432/sqli_lab", "sqli_demo_reader", ""), business))
                .isInstanceOf(IllegalArgumentException.class);
        assertThatThrownBy(() -> new SqliLabRepository(
                new SqliLabProperties("jdbc:postgresql://sqli-lab-db:5432/sqli_lab?user=admin", "sqli_demo_reader", "test-only-password"), business))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    void enabledLabFailsClosedBeforeServingRequestsWithWrongConfiguration() {
        contextRunner.withInitializer(context -> context.getEnvironment().setActiveProfiles("sqli-lab"))
                .withPropertyValues("app.demo.sqli.enabled=true", "spring.datasource.url=jdbc:h2:mem:business",
                        "app.demo.sqli.jdbc-url=jdbc:h2:mem:lab", "app.demo.sqli.username=sqli_demo_reader",
                        "app.demo.sqli.password=test-only-password")
                .run(context -> assertThat(context).hasFailed());
    }

    @Test
    void propertiesNeverIncludeCredentialsInToString() {
        assertThat(new SqliLabProperties("test-url", "test-user", "test-password").toString())
                .doesNotContain("test-url", "test-user", "test-password");
    }

    @Test
    void stackedStatementsAreRefusedBeforeOpeningAnyDatabaseConnection() {
        SqliLabRepository repository = new SqliLabRepository(new SqliLabProperties(
                "jdbc:postgresql://not-a-real-lab-host:5432/sqli_lab", "sqli_demo_reader", "test-only-password"),
                "jdbc:postgresql://postgres:5432/blogdb");
        assertThatThrownBy(() -> repository.search("'; ALTER ROLE sqli_demo_reader NOLOGIN; -- "))
                .isInstanceOf(SqliLabRepository.LabQueryException.class).hasMessage("Demo query rejected");
    }
}
