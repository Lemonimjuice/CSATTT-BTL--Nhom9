package com.blogapi.dto.response;

import com.blogapi.entity.Post.Status;
import com.blogapi.entity.User.Role;

import java.time.LocalDateTime;
import java.util.List;

public class Responses {

    // ── Auth ─────────────────────────────────────────────────────────────────

    public record AuthResponse(
            String accessToken,
            String refreshToken,
            String tokenType,
            UserSummary user
    ) {
        public static AuthResponse of(String access, String refresh, UserSummary user) {
            return new AuthResponse(access, refresh, "Bearer", user);
        }
    }

    public record RefreshResponse(String accessToken, String tokenType) {
        public static RefreshResponse of(String access) {
            return new RefreshResponse(access, "Bearer");
        }
    }

    // ── User ─────────────────────────────────────────────────────────────────

    public record UserSummary(Long id, String username, String email, Role role) {}

    // ── Category ─────────────────────────────────────────────────────────────

    public record CategoryResponse(
            Long id,
            String name,
            String slug,
            String description,
            long postCount,
            LocalDateTime createdAt
    ) {}

    // ── Post ─────────────────────────────────────────────────────────────────

    public record PostSummaryResponse(
            Long id,
            String title,
            String slug,
            String summary,
            Status status,
            UserSummary author,
            CategoryResponse category,
            long commentCount,
            LocalDateTime createdAt,
            LocalDateTime updatedAt
    ) {}

    public record PostDetailResponse(
            Long id,
            String title,
            String slug,
            String content,
            String summary,
            Status status,
            UserSummary author,
            CategoryResponse category,
            long commentCount,
            LocalDateTime createdAt,
            LocalDateTime updatedAt
    ) {}

    // ── Comment ──────────────────────────────────────────────────────────────

    public record CommentResponse(
            Long id,
            String content,
            boolean deleted,
            UserSummary author,
            Long parentId,
            int depth,
            List<CommentResponse> replies,
            LocalDateTime createdAt,
            LocalDateTime updatedAt
    ) {}

    // ── Page wrapper ─────────────────────────────────────────────────────────

    public record PageResponse<T>(
            List<T> content,
            int page,
            int size,
            long totalElements,
            int totalPages,
            boolean last
    ) {}
}
