package com.blogapi;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.blogapi.security.JwtAuthenticationFilter;
import com.blogapi.security.JwtService;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.core.userdetails.UserDetailsService;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

class JwtAuthenticationLoggingTest {
    @Test
    void parserExceptionCannotLeakSubmittedTokenToLogs() throws Exception {
        JwtService jwtService = mock(JwtService.class);
        String token = "sensitive-test-token";
        when(jwtService.extractUsername(token)).thenThrow(new IllegalArgumentException("Rejected " + token));
        JwtAuthenticationFilter filter = new JwtAuthenticationFilter(jwtService, mock(UserDetailsService.class));
        Logger logger = (Logger) LoggerFactory.getLogger(JwtAuthenticationFilter.class);
        ListAppender<ILoggingEvent> appender = new ListAppender<>();
        appender.start();
        logger.addAppender(appender);
        try {
            MockHttpServletRequest request = new MockHttpServletRequest("GET", "/api/v1/secure/records/1");
            request.addHeader("Authorization", "Bearer " + token);
            filter.doFilter(request, new MockHttpServletResponse(), (req, res) -> { });
            assertThat(appender.list).hasSize(1);
            assertThat(appender.list.get(0).getFormattedMessage()).isEqualTo("JWT authentication failed");
            assertThat(appender.list.get(0).getThrowableProxy()).isNull();
        } finally {
            logger.detachAppender(appender);
            appender.stop();
        }
    }
}
