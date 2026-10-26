package com.blogapi.service.impl;

import com.blogapi.config.JwtProperties;
import com.blogapi.dto.request.AuthRequests.*;
import com.blogapi.dto.response.Responses.*;
import com.blogapi.entity.RefreshToken;
import com.blogapi.entity.User;
import com.blogapi.exception.DuplicateResourceException;
import com.blogapi.exception.TokenException;
import com.blogapi.repository.RefreshTokenRepository;
import com.blogapi.repository.UserRepository;
import com.blogapi.security.JwtService;
import com.blogapi.service.AuthService;
import com.blogapi.util.EntityMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.security.core.userdetails.UserDetailsService;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.Instant;
import java.util.UUID;

@Service
@RequiredArgsConstructor
@Slf4j
public class AuthServiceImpl implements AuthService {

    private final UserRepository         userRepository;
    private final RefreshTokenRepository refreshTokenRepository;
    private final PasswordEncoder        passwordEncoder;
    private final AuthenticationManager  authManager;
    private final JwtService             jwtService;
    private final UserDetailsService     userDetailsService;
    private final JwtProperties          jwtProperties;

    @Override
    @Transactional
    public AuthResponse register(RegisterRequest request) {
        if (userRepository.existsByUsername(request.username()))
            throw new DuplicateResourceException("Username already taken: " + request.username());
        if (userRepository.existsByEmail(request.email()))
            throw new DuplicateResourceException("Email already registered: " + request.email());

        User user = User.builder()
                .username(request.username())
                .email(request.email())
                .password(passwordEncoder.encode(request.password()))
                .build();

        user = userRepository.save(user);
        log.info("New user registered: {}", user.getUsername());

        return buildAuthResponse(user);
    }

    @Override
    @Transactional
    public AuthResponse login(LoginRequest request) {
        authManager.authenticate(
                new UsernamePasswordAuthenticationToken(request.username(), request.password()));

        User user = userRepository.findByUsername(request.username()).orElseThrow();
        log.info("User logged in: {}", user.getUsername());
        return buildAuthResponse(user);
    }

    @Override
    @Transactional
    public RefreshResponse refresh(RefreshTokenRequest request) {
        RefreshToken stored = refreshTokenRepository.findByToken(request.refreshToken())
                .orElseThrow(() -> new TokenException("Invalid refresh token"));

        if (stored.getExpiresAt().isBefore(Instant.now())) {
            refreshTokenRepository.delete(stored);
            throw new TokenException("Refresh token expired — please log in again");
        }

        UserDetails userDetails = userDetailsService.loadUserByUsername(stored.getUser().getUsername());
        if (!userDetails.isEnabled())
            throw new TokenException("Account is disabled");
        String newAccess = jwtService.generateAccessToken(userDetails);
        log.debug("Access token refreshed for user: {}", stored.getUser().getUsername());
        return RefreshResponse.of(newAccess);
    }

    @Override
    @Transactional
    public void logout(RefreshTokenRequest request) {
        refreshTokenRepository.findByToken(request.refreshToken())
                .ifPresent(refreshTokenRepository::delete);
        log.info("User logged out (refresh token revoked)");
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private AuthResponse buildAuthResponse(User user) {
        UserDetails userDetails = userDetailsService.loadUserByUsername(user.getUsername());
        String accessToken  = jwtService.generateAccessToken(userDetails);
        String refreshToken = createRefreshToken(user);
        return AuthResponse.of(accessToken, refreshToken, EntityMapper.toUserSummary(user));
    }

    private String createRefreshToken(User user) {
        // Delete any existing refresh token for this user
        refreshTokenRepository.deleteByUser(user);

        RefreshToken token = RefreshToken.builder()
                .token(UUID.randomUUID().toString())
                .user(user)
                .expiresAt(Instant.now().plusMillis(jwtProperties.getRefreshTokenExpirationMs()))
                .build();

        return refreshTokenRepository.save(token).getToken();
    }
}
