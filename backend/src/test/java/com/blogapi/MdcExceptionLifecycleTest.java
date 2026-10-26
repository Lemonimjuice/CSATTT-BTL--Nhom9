package com.blogapi;

import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.blogapi.config.MdcLoggingFilter;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.slf4j.LoggerFactory;
import org.slf4j.MDC;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.io.IOException;

import static org.assertj.core.api.Assertions.*;

class MdcExceptionLifecycleTest {
    @ParameterizedTest
    @ValueSource(booleans = {false, true})
    void escapedExceptionLogsOnceAndPreservesAlreadyCommittedStatus(boolean committed) throws Exception {
        Logger logger = (Logger) LoggerFactory.getLogger(MdcLoggingFilter.class);
        ListAppender<ILoggingEvent> appender = new ListAppender<>();
        appender.start(); logger.addAppender(appender);
        try {
            MockHttpServletRequest request = new MockHttpServletRequest("GET", "/exception-fixture");
            request.addHeader("X-Request-ID", "exception-unit-fixture");
            MockHttpServletResponse response = new MockHttpServletResponse();
            if (committed) { response.setStatus(202); response.flushBuffer(); }
            assertThatThrownBy(() -> new MdcLoggingFilter().doFilter(request, response, (req, res) -> {
                throw new IOException("synthetic exception fixture");
            })).isInstanceOf(IOException.class);
            int expected = committed ? 202 : 500;
            assertThat(response.getStatus()).isEqualTo(expected);
            assertThat(appender.list).hasSize(1);
            assertThat(appender.list.get(0).getFormattedMessage()).contains(" -> " + expected)
                    .doesNotContain("synthetic exception fixture");
            assertThat(appender.list.get(0).getThrowableProxy()).isNull();
            assertThat(MDC.getCopyOfContextMap()).isNullOrEmpty();
        } finally { logger.detachAppender(appender); appender.stop(); MDC.clear(); }
    }
}
