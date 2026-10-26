package com.blogapi.controller;

import com.blogapi.dto.request.CommentRequests.*;
import com.blogapi.dto.response.Responses.*;
import com.blogapi.service.CommentService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;

@RestController
@RequestMapping("/api/v1")
@RequiredArgsConstructor
@Slf4j
public class CommentController {

    private final CommentService commentService;

    /**
     * GET /api/v1/posts/{postId}/comments
     * Returns paginated top-level comments, each with full nested reply tree.
     */
    @GetMapping("/posts/{postId}/comments")
    public ResponseEntity<PageResponse<CommentResponse>> getByPost(
            @PathVariable Long postId,
            @RequestParam(defaultValue = "0")  int page,
            @RequestParam(defaultValue = "20") int size,
            @AuthenticationPrincipal UserDetails userDetails) {
        return ResponseEntity.ok(commentService.getByPost(
                postId, PageRequest.of(page, Math.min(size, 100),
                        Sort.by(Sort.Direction.ASC, "createdAt")),
                userDetails == null ? null : userDetails.getUsername()));
    }

    /**
     * GET /api/v1/comments/{id}
     * Returns a single comment with its full nested reply tree.
     */
    @GetMapping("/comments/{id}")
    public ResponseEntity<CommentResponse> getById(@PathVariable Long id,
                                                  @AuthenticationPrincipal UserDetails userDetails) {
        return ResponseEntity.ok(commentService.getById(id, userDetails == null ? null : userDetails.getUsername()));
    }

    /**
     * POST /api/v1/posts/{postId}/comments
     * Body: { "content": "...", "parentId": null }   ← top-level comment
     * Body: { "content": "...", "parentId": 42 }     ← reply to comment 42
     */
    @PostMapping("/posts/{postId}/comments")
    public ResponseEntity<CommentResponse> create(
            @PathVariable Long postId,
            @Valid @RequestBody CreateCommentRequest request,
            @AuthenticationPrincipal UserDetails userDetails) {
        log.debug("Comment on post {} by {}, parentId={}", postId, userDetails.getUsername(), request.parentId());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(commentService.create(postId, request, userDetails.getUsername()));
    }

    /**
     * PUT /api/v1/comments/{id}
     * Only the comment author or a MODERATOR/ADMIN can update.
     */
    @PutMapping("/comments/{id}")
    public ResponseEntity<CommentResponse> update(
            @PathVariable Long id,
            @Valid @RequestBody UpdateCommentRequest request,
            @AuthenticationPrincipal UserDetails userDetails) {
        return ResponseEntity.ok(commentService.update(id, request, userDetails.getUsername()));
    }

    /**
     * DELETE /api/v1/comments/{id}
     * Soft-delete — content replaced with [deleted], thread structure preserved.
     */
    @DeleteMapping("/comments/{id}")
    public ResponseEntity<Void> delete(
            @PathVariable Long id,
            @AuthenticationPrincipal UserDetails userDetails) {
        commentService.delete(id, userDetails.getUsername());
        return ResponseEntity.noContent().build();
    }
}
