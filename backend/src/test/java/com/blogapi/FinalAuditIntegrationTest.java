package com.blogapi;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.AppenderBase;
import com.blogapi.config.MdcLoggingFilter;
import com.blogapi.entity.User;
import com.blogapi.repository.RefreshTokenRepository;
import com.blogapi.repository.UserRepository;
import com.blogapi.security.JwtService;
import com.blogapi.security.UserDetailsServiceImpl;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.*;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.web.servlet.ServletRegistrationBean;
import org.springframework.context.annotation.*;
import org.springframework.http.*;
import org.springframework.http.client.JdkClientHttpRequestFactory;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.*;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

import static org.assertj.core.api.Assertions.assertThat;

@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@ActiveProfiles("audit-test")
@Import({FinalAuditIntegrationTest.FaultFixtures.class, FinalAuditIntegrationTest.HandledFixture.class})
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:finalaudit;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa", "spring.datasource.password=", "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.jpa.hibernate.ddl-auto=create-drop", "spring.jpa.show-sql=false",
        "spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.H2Dialect",
        "app.jwt.secret=cmVjb3JkLWFwaS10ZXN0LXNpZ25pbmcta2V5LWF0LWxlYXN0LTMyLWJ5dGVzLWxvbmc=",
        "logging.level.org.hibernate.SQL=OFF", "logging.level.com.blogapi=DEBUG"
})
class FinalAuditIntegrationTest {
    @Autowired TestRestTemplate http;
    @Autowired UserRepository users;
    @Autowired RefreshTokenRepository refresh;
    @Autowired JwtService jwt;
    @Autowired UserDetailsServiceImpl details;
    @Autowired PasswordEncoder passwords;
    private final Events events = new Events();
    private String token;
    private static final String PASSWORD = "audit-password-fixture";

    @BeforeEach
    void setUp() {
        http.getRestTemplate().setRequestFactory(new JdkClientHttpRequestFactory());
        refresh.deleteAll(); users.deleteAll();
        users.save(User.builder().username("audit-user").email("audit@example.test").password(passwords.encode(PASSWORD))
                .role(User.Role.USER).enabled(true).build());
        token = jwt.generateAccessToken(details.loadUserByUsername("audit-user"));
        events.start(); logger().addAppender(events);
    }
    @AfterEach void close() { logger().detachAppender(events); events.stop(); }

    @Test
    void loginSuccessAuditsUsernamePeerIpAndRequestIdWithoutTokens() {
        ResponseEntity<String> response = http.exchange("/api/v1/auth/login", HttpMethod.POST,
                new HttpEntity<>("{\"username\":\"audit-user\",\"password\":\"" + PASSWORD + "\"}", headers("login-ok", false)), String.class);
        assertThat(response.getStatusCode().value()).isEqualTo(200);
        ILoggingEvent event = event("event=login_success");
        assertThat(event.getFormattedMessage()).contains("username=audit-user");
        assertAudit(event, "login-ok");
        assertSafe();
        // Auth response tokens must never appear in any application log.
        try {
            var tree = new com.fasterxml.jackson.databind.ObjectMapper().readTree(response.getBody());
            for (ILoggingEvent entry : events.items) {
                assertThat(entry.getFormattedMessage()).doesNotContain(tree.get("accessToken").asText(), tree.get("refreshToken").asText());
            }
        } catch (java.io.IOException ex) { throw new AssertionError("Auth response was not JSON", ex); }
    }

    @ParameterizedTest
    @ValueSource(strings = {"audit-user", "unknown-user", "audit-user\r\nspoofed"})
    void loginFailureHasSanitizedUsernameAndNoPassword(String username) throws Exception {
        String body = new com.fasterxml.jackson.databind.ObjectMapper().writeValueAsString(
                java.util.Map.of("username", username, "password", "wrong-password-fixture"));
        ResponseEntity<String> response = http.exchange("/api/v1/auth/login", HttpMethod.POST,
                new HttpEntity<>(body, headers("login-failed", false)), String.class);
        assertThat(response.getStatusCode().value()).isEqualTo(401);
        ILoggingEvent event = event("event=login_failure");
        assertThat(event.getFormattedMessage()).contains("username=" + username.replace('\r', '_').replace('\n', '_'));
        assertAudit(event, "login-failed"); assertSafe();
        for (ILoggingEvent entry : events.items) assertThat(entry.getFormattedMessage()).doesNotContain("\r", "\n");
    }

    @ParameterizedTest
    @ValueSource(strings = {"anonymous", "invalid", "role"})
    void backendDenialsHaveOneCorrelatedAccessEventAndIgnoreForwardedIp(String mode) {
        HttpHeaders headers = headers("deny-" + mode, mode.equals("role"));
        if (mode.equals("invalid")) headers.setBearerAuth("invalid-audit-fixture-token");
        String path = mode.equals("role") ? "/api/v1/categories" : "/api/v1/secure/records/1";
        ResponseEntity<String> response = http.exchange(path, mode.equals("role") ? HttpMethod.POST : HttpMethod.GET,
                new HttpEntity<>("{\"name\":\"body-secret-fixture\"}", headers), String.class);
        int expected = mode.equals("role") ? 403 : 401;
        assertThat(response.getStatusCode().value()).isEqualTo(expected);
        assertAccess(response, "deny-" + mode, expected); assertSafe();
    }

    @Test
    void uncaughtServletExceptionStillHasOne500AccessLogAndCleanup() {
        ResponseEntity<String> response = http.exchange("/test/uncaught", HttpMethod.GET,
                new HttpEntity<>(headers("uncaught-fixture", true)), String.class);
        assertThat(response.getStatusCode().value()).isEqualTo(500);
        assertAccess(response, "uncaught-fixture", 500); assertSafe();
        events.items.clear();
        ResponseEntity<String> next = http.exchange("/actuator/health", HttpMethod.GET,
                new HttpEntity<>(headers("after-exception", false)), String.class);
        assertThat(next.getStatusCode().value()).isEqualTo(200);
        assertAccess(next, "after-exception", 200);
        assertThat(access().get(0).getMDCPropertyMap()).doesNotContainKey("userId");
    }

    @Test
    void handledExceptionDoesNotLogSensitiveExceptionText() {
        ResponseEntity<String> response = http.exchange("/test/handled", HttpMethod.GET,
                new HttpEntity<>(headers("handled-fixture", true)), String.class);
        assertThat(response.getStatusCode().value()).isEqualTo(500);
        assertAccess(response, "handled-fixture", 500);
        for (ILoggingEvent entry : events.items) {
            assertThat(entry.getFormattedMessage()).doesNotContain("private-exception-fixture");
            assertThat(entry.getThrowableProxy()).isNull();
        }
    }

    private HttpHeaders headers(String id, boolean authenticated) {
        HttpHeaders headers = new HttpHeaders(); headers.setContentType(MediaType.APPLICATION_JSON);
        headers.set("X-Request-ID", id); headers.set("X-Real-IP", "198.51.100.99"); headers.set("X-Forwarded-For", "198.51.100.99");
        if (authenticated) headers.setBearerAuth(token);
        return headers;
    }
    private void assertAccess(ResponseEntity<String> response, String id, int status) {
        assertThat(response.getHeaders().getFirst("X-Request-ID")).isEqualTo(id);
        assertThat(response.getHeaders().getFirst("X-Blocked-By")).isNull();
        assertThat(access()).hasSize(1);
        assertThat(access().get(0).getFormattedMessage()).contains(" -> " + status);
        assertAudit(access().get(0), id);
    }
    private void assertAudit(ILoggingEvent event, String id) {
        assertThat(event.getMDCPropertyMap().get("requestId")).isEqualTo(id);
        assertThat(event.getMDCPropertyMap().get("clientIp")).isIn("127.0.0.1", "::1", "0:0:0:0:0:0:0:1");
        assertThat(event.getFormattedMessage()).contains("ip=").doesNotContain("198.51.100.99");
    }
    private void assertSafe() {
        for (ILoggingEvent event : events.items) assertThat(event.getFormattedMessage())
                .doesNotContain(PASSWORD, "wrong-password-fixture", token, "invalid-audit-fixture-token", "body-secret-fixture");
    }
    private ILoggingEvent event(String marker) {
        List<ILoggingEvent> matching = events.items.stream().filter(e -> e.getFormattedMessage().contains(marker)).toList();
        assertThat(matching).hasSize(1);
        return matching.get(0);
    }
    private List<ILoggingEvent> access() {
        return events.items.stream().filter(e -> e.getLoggerName().equals(MdcLoggingFilter.class.getName())).toList();
    }
    private Logger logger() { return (Logger) LoggerFactory.getLogger("com.blogapi"); }
    private static class Events extends AppenderBase<ILoggingEvent> {
        final List<ILoggingEvent> items = new CopyOnWriteArrayList<>();
        @Override protected void append(ILoggingEvent e) { e.prepareForDeferredProcessing(); items.add(e); }
    }

    @TestConfiguration
    static class FaultFixtures {
        @Bean ServletRegistrationBean<HttpServlet> uncaughtFixture() {
            return new ServletRegistrationBean<>(new HttpServlet() {
                @Override protected void doGet(HttpServletRequest req, HttpServletResponse resp) throws ServletException {
                    throw new ServletException("synthetic uncaught fixture");
                }
            }, "/test/uncaught");
        }
    }
    // Test-only profile prevents this fixture controller from entering other contexts or production.
    @RestController
    @Profile("audit-test")
    static class HandledFixture {
        @GetMapping("/test/handled") String fail() { throw new IllegalStateException("private-exception-fixture"); }
    }
}
