package com.blogapi.dto.request;

import jakarta.validation.constraints.Email;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public class AuthRequests {

    public record RegisterRequest(
            @NotBlank(message = "Username is required")
            @Size(min = 3, max = 50, message = "Username must be 3-50 characters")
            String username,

            @NotBlank(message = "Email is required")
            @Email(message = "Invalid email format")
            String email,

            @NotBlank(message = "Password is required")
            @Size(min = 8, message = "Password must be at least 8 characters")
            String password
    ) {}

    public record LoginRequest(
            @NotBlank(message = "Username is required")
            String username,

            @NotBlank(message = "Password is required")
            String password
    ) {}

    public record RefreshTokenRequest(
            @NotBlank(message = "Refresh token is required")
            String refreshToken
    ) {}
}
