package com.blogapi.demo;

import jakarta.validation.constraints.NotBlank;
import org.springframework.boot.context.properties.ConfigurationProperties;
import org.springframework.validation.annotation.Validated;

@Validated
@ConfigurationProperties(prefix = "app.demo.sqli")
public record SqliLabProperties(@NotBlank String jdbcUrl,
                                @NotBlank String username,
                                @NotBlank String password) {
    @Override
    public String toString() { return "SqliLabProperties[redacted]"; }
}
