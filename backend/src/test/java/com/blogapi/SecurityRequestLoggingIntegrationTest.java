package com.blogapi;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.AppenderBase;
import com.blogapi.config.MdcLoggingFilter;
import com.blogapi.entity.User;
import com.blogapi.repository.RecordRepository;
import com.blogapi.repository.UserRepository;
import com.blogapi.security.JwtAuthenticationFilter;
import com.blogapi.security.JwtService;
import com.blogapi.security.UserDetailsServiceImpl;
import jakarta.servlet.ServletContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.web.client.TestRestTemplate;
import org.springframework.boot.web.servlet.DelegatingFilterProxyRegistrationBean;
import org.springframework.core.annotation.OrderUtils;
import org.springframework.http.*;
import org.springframework.security.web.FilterChainProxy;
import org.springframework.test.context.TestPropertySource;

import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;

import static org.assertj.core.api.Assertions.assertThat;

/** Actual embedded servlet container + actual Spring Security chain; no mocked filters. */
@SpringBootTest(webEnvironment = SpringBootTest.WebEnvironment.RANDOM_PORT)
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:securitylogging;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa", "spring.datasource.password=",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.jpa.hibernate.ddl-auto=create-drop", "spring.jpa.show-sql=false",
        "spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.H2Dialect",
        "app.jwt.secret=cmVjb3JkLWFwaS10ZXN0LXNpZ25pbmcta2V5LWF0LWxlYXN0LTMyLWJ5dGVzLWxvbmc=",
        "logging.level.org.hibernate.SQL=OFF"
})
class SecurityRequestLoggingIntegrationTest {
    @Autowired TestRestTemplate http;
    @Autowired ServletContext servletContext;
    @Autowired DelegatingFilterProxyRegistrationBean securityFilterChainRegistration;
    @Autowired FilterChainProxy springSecurityFilterChain;
    @Autowired UserRepository users;
    @Autowired RecordRepository records;
    @Autowired JwtService jwt;
    @Autowired UserDetailsServiceImpl userDetails;
    private final Events events = new Events();
    private String token;

    @BeforeEach
    void setUp() {
        records.deleteAll();
        users.deleteAll();
        users.save(User.builder().username("logging-user").email("logging@example.test")
                .password("unused-jwt-only-test-fixture").role(User.Role.USER).enabled(true).build());
        token = jwt.generateAccessToken(userDetails.loadUserByUsername("logging-user"));
        events.start();
        logger(MdcLoggingFilter.class).addAppender(events);
        logger(JwtAuthenticationFilter.class).addAppender(events);
    }

    @AfterEach
    void detach() {
        logger(MdcLoggingFilter.class).detachAppender(events);
        logger(JwtAuthenticationFilter.class).detachAppender(events);
        events.stop();
    }

    @Test
    void registeredExactlyOnceOutsideSecurityChainAndBeforeIt() {
        assertThat(servletContext.getFilterRegistrations().values().stream()
                .filter(f -> f.getClassName().equals(MdcLoggingFilter.class.getName())).count()).isEqualTo(1);
        assertThat(springSecurityFilterChain.getFilterChains().stream()
                .flatMap(chain -> chain.getFilters().stream()).filter(MdcLoggingFilter.class::isInstance).count()).isZero();
        assertThat(OrderUtils.getOrder(MdcLoggingFilter.class)).isLessThan(securityFilterChainRegistration.getOrder());
    }

    @ParameterizedTest
    @ValueSource(strings = {"missing", "invalid"})
    void security401HasRequestIdAndExactlyOneAccessEvent(String kind) {
        HttpHeaders headers = headers(kind.equals("missing") ? "security-missing" : "invalid request id");
        if (kind.equals("invalid")) headers.setBearerAuth("not-a-jwt-logging-fixture");
        ResponseEntity<String> response = http.exchange("/api/v1/secure/records", HttpMethod.POST,
                new HttpEntity<>("{\"content\":\"body-marker\",\"password\":\"password-marker\"}", headers), String.class);
        assertThat(response.getStatusCode().value()).isEqualTo(401);
        String id = response.getHeaders().getFirst("X-Request-ID");
        if (kind.equals("missing")) assertThat(id).isEqualTo("security-missing");
        else assertThat(id).matches("[a-f0-9-]{36}");
        assertAccess(response, id, "/api/v1/secure/records", 401);
        if (kind.equals("invalid")) {
            List<ILoggingEvent> jwtEvents = events.items.stream()
                    .filter(e -> e.getLoggerName().equals(JwtAuthenticationFilter.class.getName())).toList();
            assertThat(jwtEvents).hasSize(1);
            assertThat(jwtEvents.stream()
                    .allMatch(e -> id.equals(e.getMDCPropertyMap().get("requestId")))).isTrue();
        }
    }

    @Test
    void roleDeniedBySecurityHasRequestIdAndOneAccessEvent() {
        HttpHeaders headers = headers("security-role-denied");
        headers.setBearerAuth(token);
        ResponseEntity<String> response = http.exchange("/api/v1/categories", HttpMethod.POST,
                new HttpEntity<>("{\"name\":\"body-marker\",\"password\":\"password-marker\"}", headers), String.class);
        assertThat(response.getStatusCode().value()).isEqualTo(403);
        assertAccess(response, "security-role-denied", "/api/v1/categories", 403);
        assertThat(accessEvent().getMDCPropertyMap().get("userId")).isEqualTo("logging-user");
    }

    @Test
    void backendOwnership403IsCorrelatedAndNotMarkedAsWaf() {
        User other = users.save(User.builder().username("logging-other").email("other@logging.example.test")
                .password("unused-jwt-only-test-fixture").role(User.Role.USER).enabled(true).build());
        long recordId = records.save(com.blogapi.entity.Record.builder().owner(other).content("body-marker").build()).getId();
        HttpHeaders headers = headers("backend-ownership-denied");
        headers.setBearerAuth(token);
        String path = "/api/v1/secure/records/" + recordId;
        ResponseEntity<String> response = http.exchange(path, HttpMethod.GET, new HttpEntity<>(headers), String.class);
        assertThat(response.getStatusCode().value()).isEqualTo(403);
        assertAccess(response, "backend-ownership-denied", path, 403);
        assertThat(accessEvent().getMDCPropertyMap().get("userId")).isEqualTo("logging-user");
    }

    @Test
    void nextRequestDoesNotReusePreviousRequestId() {
        HttpHeaders firstHeaders = headers("first-health-id");
        firstHeaders.setBearerAuth(token);
        ResponseEntity<String> first = http.exchange("/actuator/health", HttpMethod.GET,
                new HttpEntity<>(firstHeaders), String.class);
        assertAccess(first, "first-health-id", "/actuator/health", 200);
        assertThat(accessEvent().getMDCPropertyMap().get("userId")).isEqualTo("logging-user");
        events.items.clear();
        ResponseEntity<String> second = http.getForEntity("/actuator/health", String.class);
        String id = second.getHeaders().getFirst("X-Request-ID");
        assertThat(id).matches("[a-f0-9-]{36}").isNotEqualTo("first-health-id");
        assertAccess(second, id, "/actuator/health", 200);
        assertThat(accessEvent().getMDCPropertyMap()).doesNotContainKey("userId");
    }

    @Test
    void directErrorUrlStillRequiresAuthentication() {
        ResponseEntity<String> response = http.getForEntity("/error", String.class);
        assertThat(response.getStatusCode().value()).isEqualTo(401);
    }

    private void assertAccess(ResponseEntity<String> response, String id, String path, int status) {
        assertThat(response.getHeaders().getFirst("X-Request-ID")).isEqualTo(id);
        assertThat(response.getHeaders().getFirst("X-Blocked-By")).isNull();
        List<ILoggingEvent> access = events.items.stream()
                .filter(e -> e.getLoggerName().equals(MdcLoggingFilter.class.getName())).toList();
        assertThat(access).hasSize(1);
        assertThat(access.get(0).getMDCPropertyMap().get("requestId")).isEqualTo(id);
        assertThat(access.get(0).getFormattedMessage()).contains(path + " -> " + status);
        for (ILoggingEvent event : events.items) {
            assertThat(event.getFormattedMessage()).doesNotContain(token, "not-a-jwt-logging-fixture", "password-marker", "body-marker");
            assertThat(event.getMDCPropertyMap().toString()).doesNotContain(token, "password-marker", "body-marker");
        }
    }

    private HttpHeaders headers(String id) {
        HttpHeaders headers = new HttpHeaders();
        headers.setContentType(MediaType.APPLICATION_JSON);
        headers.set("X-Request-ID", id);
        return headers;
    }

    private ILoggingEvent accessEvent() {
        return events.items.stream().filter(e -> e.getLoggerName().equals(MdcLoggingFilter.class.getName()))
                .findFirst().orElseThrow();
    }

    private Logger logger(Class<?> type) { return (Logger) LoggerFactory.getLogger(type); }

    private static final class Events extends AppenderBase<ILoggingEvent> {
        private final List<ILoggingEvent> items = new CopyOnWriteArrayList<>();
        @Override protected void append(ILoggingEvent event) {
            event.prepareForDeferredProcessing();
            items.add(event);
        }
    }
}
