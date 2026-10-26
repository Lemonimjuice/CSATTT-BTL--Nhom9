package com.blogapi;

import com.blogapi.config.MdcLoggingFilter;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;
import org.slf4j.MDC;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

class MdcLoggingFilterTest {
    private final MdcLoggingFilter filter = new MdcLoggingFilter();

    @Test
    void preservesProxyIdAndNeverCopiesAuthorizationOrBodyToMdc() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/api/v1/auth/login");
        request.addHeader("X-Request-ID", "proxy_01.demo-abc");
        request.addHeader("Authorization", "Bearer private-test-token");
        request.setContent("{\"password\":\"private-test-password\"}".getBytes(java.nio.charset.StandardCharsets.UTF_8));
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request, response, (req, res) -> {
            assertThat(MDC.get("requestId")).isEqualTo("proxy_01.demo-abc");
            assertThat(MDC.getCopyOfContextMap().toString()).doesNotContain("private-test");
        });
        assertThat(response.getHeader("X-Request-ID")).isEqualTo("proxy_01.demo-abc");
        assertThat(MDC.getCopyOfContextMap()).isNullOrEmpty();
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {"bad\r\nforged", "bad\tvalue", "bad value", "bad/uri", "é", ".invalid",
            "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"})
    void replacesUntrustedIdAndCleansUpEvenWhenChainThrows(String untrusted) {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/actuator/health");
        if (untrusted != null) request.addHeader("X-Request-ID", untrusted);
        MockHttpServletResponse response = new MockHttpServletResponse();
        assertThatThrownBy(() -> filter.doFilter(request, response, (req, res) -> {
            assertThat(MDC.get("requestId")).matches("[a-f0-9-]{36}");
            throw new jakarta.servlet.ServletException("test chain failure");
        })).isInstanceOf(jakarta.servlet.ServletException.class);
        assertThat(response.getHeader("X-Request-ID")).matches("[a-f0-9-]{36}");
        assertThat(MDC.getCopyOfContextMap()).isNullOrEmpty();
    }

    @Test
    void acceptsMaximumLengthId() throws Exception {
        String id = "a".repeat(64);
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/actuator/health");
        request.addHeader("X-Request-ID", id);
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request, response, (req, res) -> assertThat(MDC.get("requestId")).isEqualTo(id));
        assertThat(response.getHeader("X-Request-ID")).isEqualTo(id);
    }
}
