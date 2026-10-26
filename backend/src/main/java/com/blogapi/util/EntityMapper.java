package com.blogapi.util;

import com.blogapi.dto.response.Responses.*;
import com.blogapi.entity.Category;
import com.blogapi.entity.Comment;
import com.blogapi.entity.Post;
import com.blogapi.entity.User;

import java.util.Collections;
import java.util.List;

public final class EntityMapper {

    private EntityMapper() {}

    // ── User ─────────────────────────────────────────────────────────────────

    public static UserSummary toUserSummary(User user) {
        if (user == null) return null;
        return new UserSummary(user.getId(), user.getUsername(), user.getEmail(), user.getRole());
    }

    public static PublicUserSummary toPublicUserSummary(User user) {
        if (user == null) return null;
        return new PublicUserSummary(user.getId(), user.getUsername(), user.getRole());
    }

    // ── Category ─────────────────────────────────────────────────────────────

    public static CategoryResponse toCategoryResponse(Category c) {
        if (c == null) return null;
        long postCount = c.getPosts() == null ? 0 : c.getPosts().size();
        return new CategoryResponse(c.getId(), c.getName(), c.getSlug(),
                c.getDescription(), postCount, c.getCreatedAt());
    }

    // ── Post ─────────────────────────────────────────────────────────────────

    public static PostSummaryResponse toPostSummary(Post p) {
        long commentCount = p.getComments() == null ? 0 : p.getComments().stream()
                .filter(c -> !c.isDeleted()).count();
        return new PostSummaryResponse(
                p.getId(), p.getTitle(), p.getSlug(), p.getSummary(), p.getStatus(),
                toPublicUserSummary(p.getAuthor()), toCategoryResponse(p.getCategory()),
                commentCount, p.getCreatedAt(), p.getUpdatedAt());
    }

    public static PostDetailResponse toPostDetail(Post p) {
        long commentCount = p.getComments() == null ? 0 : p.getComments().stream()
                .filter(c -> !c.isDeleted()).count();
        return new PostDetailResponse(
                p.getId(), p.getTitle(), p.getSlug(), p.getContent(), p.getSummary(),
                p.getStatus(), toPublicUserSummary(p.getAuthor()), toCategoryResponse(p.getCategory()),
                commentCount, p.getCreatedAt(), p.getUpdatedAt());
    }

    // ── Comment ──────────────────────────────────────────────────────────────

    /**
     * Maps a comment recursively, building nested replies tree.
     * Soft-deleted comments show placeholder text.
     */
    public static CommentResponse toCommentResponse(Comment c) {
        String displayContent = c.isDeleted() ? "[deleted]" : c.getContent();
        PublicUserSummary author = c.isDeleted() ? null : toPublicUserSummary(c.getAuthor());
        Long parentId = c.getParent() == null ? null : c.getParent().getId();

        List<CommentResponse> replies = (c.getReplies() == null || c.getReplies().isEmpty())
                ? Collections.emptyList()
                : c.getReplies().stream()
                        .map(EntityMapper::toCommentResponse)
                        .toList();

        return new CommentResponse(
                c.getId(), displayContent, c.isDeleted(),
                author, parentId, c.getDepth(),
                replies, c.getCreatedAt(), c.getUpdatedAt());
    }
}
