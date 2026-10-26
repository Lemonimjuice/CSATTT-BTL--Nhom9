package com.blogapi;

import com.blogapi.config.JwtProperties;
import com.blogapi.security.JwtService;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.NullAndEmptySource;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.security.core.userdetails.User;

import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;

class JwtSecretStartupTest {
    private ApplicationContextRunner context(String secret) {
        JwtProperties properties = new JwtProperties();
        properties.setSecret(secret);
        properties.setAccessTokenExpirationMs(60000);
        return new ApplicationContextRunner().withBean(JwtProperties.class, () -> properties).withBean(JwtService.class);
    }

    @ParameterizedTest
    @ValueSource(ints = {32, 48, 64})
    void validBase64KeyStartsAndSignsTokens(int bytes) {
        // Zero bytes are deliberate, deterministic test data, never a runtime secret.
        for (String secret : new String[]{Base64.getEncoder().encodeToString(new byte[bytes]),
                Base64.getEncoder().withoutPadding().encodeToString(new byte[bytes])}) {
        context(secret).run(ctx -> {
            assertThat(ctx).hasNotFailed();
            JwtService service = ctx.getBean(JwtService.class);
            var user = User.withUsername("jwt-startup-fixture").password("unused").roles("USER").build();
            String token = service.generateAccessToken(user);
            assertThat(service.isTokenValid(token, user)).isTrue();
        });
        }
    }

    @ParameterizedTest
    @NullAndEmptySource
    @ValueSource(strings = {" ", "raw-secret-with-invalid-base64-characters!", "YWJj", "!!!!", "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA==", "YWJj\n"})
    void invalidOrShortKeyFailsAtStartupWithoutLeakingTheValue(String secret) {
        context(secret).run(ctx -> {
            assertThat(ctx).hasFailed();
            Throwable failure = ctx.getStartupFailure();
            while (failure.getCause() != null) failure = failure.getCause();
            assertThat(failure.getMessage()).isEqualTo("JWT_SECRET must be Base64 encoding at least 32 bytes");
        });
    }
}
