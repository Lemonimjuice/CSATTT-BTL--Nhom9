package com.blogapi.config;

import com.blogapi.security.AuditLogValues;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.extern.slf4j.Slf4j;
import org.slf4j.MDC;
import org.springframework.core.Ordered;
import org.springframework.core.annotation.Order;
import org.springframework.lang.NonNull;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.UUID;
import java.util.regex.Pattern;

@Component
// One servlet registration, outside and before Spring Security; do not also add to its chain.
@Order(Ordered.HIGHEST_PRECEDENCE + 1)
@Slf4j
public class MdcLoggingFilter extends OncePerRequestFilter {

    // Server-only request attribute: the security context is cleared before this outer filter returns.
    public static final String AUTHENTICATED_USER_ATTRIBUTE = MdcLoggingFilter.class.getName() + ".authenticatedUser";

    private static final String REQUEST_ID_HEADER = "X-Request-ID";
    private static final Pattern SAFE_REQUEST_ID = Pattern.compile("[A-Za-z0-9][A-Za-z0-9._-]{0,63}");
    private static final String MDC_REQUEST_ID    = "requestId";
    private static final String MDC_USER_ID       = "userId";
    private static final String MDC_METHOD        = "method";
    private static final String MDC_URI           = "uri";

    @Override
    protected void doFilterInternal(
            @NonNull HttpServletRequest request,
            @NonNull HttpServletResponse response,
            @NonNull FilterChain filterChain
    ) throws ServletException, IOException {

        String requestId = request.getHeader(REQUEST_ID_HEADER);
        if (requestId == null || !SAFE_REQUEST_ID.matcher(requestId).matches()) {
            requestId = UUID.randomUUID().toString();
        }

        MDC.put(MDC_REQUEST_ID, requestId);
        MDC.put(MDC_METHOD, request.getMethod());
        MDC.put(MDC_URI, request.getRequestURI());
        // No proxy trust is configured: headers such as X-Forwarded-For are not IP evidence.
        MDC.put("clientIp", request.getRemoteAddr());

        // Add response header so clients can correlate
        response.setHeader(REQUEST_ID_HEADER, requestId);

        long start = System.currentTimeMillis();
        try {
            filterChain.doFilter(request, response);
        } catch (IOException | ServletException | RuntimeException ex) {
            // An escaped exception is a servlet 500 unless a response is already committed.
            // Do not log an exception message, stack trace, headers or body here.
            if (!response.isCommitted()) response.setStatus(HttpServletResponse.SC_INTERNAL_SERVER_ERROR);
            throw ex;
        } finally {
            try {
                // Security may already have cleared its context; retain only validated identity.
                Authentication auth = SecurityContextHolder.getContext().getAuthentication();
                Object authenticatedUser = request.getAttribute(AUTHENTICATED_USER_ATTRIBUTE);
                if (authenticatedUser instanceof String username) {
                    MDC.put(MDC_USER_ID, AuditLogValues.username(username));
                } else if (auth != null && auth.isAuthenticated() && !"anonymousUser".equals(auth.getPrincipal())) {
                    MDC.put(MDC_USER_ID, AuditLogValues.username(auth.getName()));
                }

                long elapsed = System.currentTimeMillis() - start;
                log.info("{} {} -> {} ({}ms) ip={}", request.getMethod(), request.getRequestURI(),
                        response.getStatus(), elapsed, AuditLogValues.clientIp());
            } finally {
                MDC.clear();
            }
        }
    }
}
