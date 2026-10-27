package com.blogapi.config;

import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.filter.Filter;
import ch.qos.logback.core.spi.FilterReply;

import java.util.Map;
import java.util.Set;

/**
 * Keeps the Docker healthcheck (curl to /actuator/health from inside the container every 10s) out of the
 * audit log file, where it would otherwise outnumber real events. Attached only to the audit file appender:
 * console output and health requests arriving through Nginx (non-loopback client IP) are still logged.
 */
public class LocalHealthCheckLogFilter extends Filter<ILoggingEvent> {

    private static final Set<String> LOOPBACK = Set.of("127.0.0.1", "0:0:0:0:0:0:0:1", "::1");

    @Override
    public FilterReply decide(ILoggingEvent event) {
        Map<String, String> mdc = event.getMDCPropertyMap();
        if ("/actuator/health".equals(mdc.get("uri")) && LOOPBACK.contains(mdc.get("clientIp"))) {
            return FilterReply.DENY;
        }
        return FilterReply.NEUTRAL;
    }
}
