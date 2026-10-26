package com.blogapi.service;

import com.blogapi.dto.request.AuthRequests.*;
import com.blogapi.dto.response.Responses.*;

public interface AuthService {
    AuthResponse register(RegisterRequest request);
    AuthResponse login(LoginRequest request);
    RefreshResponse refresh(RefreshTokenRequest request);
    void logout(RefreshTokenRequest request);
}
