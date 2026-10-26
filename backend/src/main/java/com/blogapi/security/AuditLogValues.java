package com.blogapi.security;

import org.slf4j.MDC;

/** Bounded display values for audit logs, never authorization decisions. */
public final class AuditLogValues {
    private AuditLogValues() { }

    public static String username(String value) {
        if (value == null) return "-";
        return value.substring(0, Math.min(value.length(), 50)).replaceAll("[^A-Za-z0-9_.@-]", "_");
    }

    public static String clientIp() {
        String value = MDC.get("clientIp");
        return value == null ? "unknown" : value;
    }
}
