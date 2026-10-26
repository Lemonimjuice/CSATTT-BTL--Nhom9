package com.blogapi.controller;

import com.blogapi.dto.request.PostRequests.*;
import com.blogapi.dto.response.Responses.*;
import com.blogapi.service.PostService;
import com.blogapi.exception.InvalidRequestException;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.PageRequest;
import org.springframework.data.domain.Pageable;
import org.springframework.data.domain.Sort;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;

import java.util.Set;

@RestController
@RequestMapping("/api/v1/posts")
@RequiredArgsConstructor
@Slf4j
public class PostController {

    private final PostService postService;
    private static final Set<String> SORT_PROPERTIES = Set.of("id", "title", "createdAt", "updatedAt");

    // ── Public reads ──────────────────────────────────────────────────────────

    /** GET /api/v1/posts?page=0&size=10&sort=createdAt,desc */
    @GetMapping
    public ResponseEntity<PageResponse<PostSummaryResponse>> getPublished(
            @RequestParam(defaultValue = "0")  int page,
            @RequestParam(defaultValue = "10") int size,
            @RequestParam(defaultValue = "createdAt,desc") String sort) {
        return ResponseEntity.ok(postService.getPublished(buildPageable(page, size, sort)));
    }

    /** GET /api/v1/posts/{id} */
    @GetMapping("/{id}")
    public ResponseEntity<PostDetailResponse> getById(@PathVariable Long id,
                                                       @AuthenticationPrincipal UserDetails userDetails) {
        return ResponseEntity.ok(postService.getById(id, userDetails == null ? null : userDetails.getUsername()));
    }

    /** GET /api/v1/posts/slug/{slug} */
    @GetMapping("/slug/{slug}")
    public ResponseEntity<PostDetailResponse> getBySlug(@PathVariable String slug,
                                                         @AuthenticationPrincipal UserDetails userDetails) {
        return ResponseEntity.ok(postService.getBySlug(slug, userDetails == null ? null : userDetails.getUsername()));
    }

    /** GET /api/v1/posts/category/{categoryId} */
    @GetMapping("/category/{categoryId}")
    public ResponseEntity<PageResponse<PostSummaryResponse>> getByCategory(
            @PathVariable Long categoryId,
            @RequestParam(defaultValue = "0")  int page,
            @RequestParam(defaultValue = "10") int size) {
        return ResponseEntity.ok(postService.getByCategory(categoryId, buildPageable(page, size, "createdAt,desc")));
    }

    /** GET /api/v1/posts/author/{authorId} */
    @GetMapping("/author/{authorId}")
    public ResponseEntity<PageResponse<PostSummaryResponse>> getByAuthor(
            @PathVariable Long authorId,
            @RequestParam(defaultValue = "0")  int page,
            @RequestParam(defaultValue = "10") int size) {
        return ResponseEntity.ok(postService.getByAuthor(authorId, buildPageable(page, size, "createdAt,desc")));
    }

    /** GET /api/v1/posts/search?q=keyword */
    @GetMapping("/search")
    public ResponseEntity<PageResponse<PostSummaryResponse>> search(
            @RequestParam("q") String keyword,
            @RequestParam(defaultValue = "0")  int page,
            @RequestParam(defaultValue = "10") int size) {
        return ResponseEntity.ok(postService.search(keyword, buildPageable(page, size, "createdAt,desc")));
    }

    // ── Authenticated ─────────────────────────────────────────────────────────

    /** GET /api/v1/posts/me — own posts (all statuses) */
    @GetMapping("/me")
    public ResponseEntity<PageResponse<PostSummaryResponse>> getMyPosts(
            @AuthenticationPrincipal UserDetails userDetails,
            @RequestParam(defaultValue = "0")  int page,
            @RequestParam(defaultValue = "10") int size) {
        return ResponseEntity.ok(postService.getMyPosts(
                userDetails.getUsername(), buildPageable(page, size, "createdAt,desc")));
    }

    /** POST /api/v1/posts */
    @PostMapping
    public ResponseEntity<PostDetailResponse> create(
            @Valid @RequestBody CreatePostRequest request,
            @AuthenticationPrincipal UserDetails userDetails) {
        log.debug("Create post request by {}", userDetails.getUsername());
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(postService.create(request, userDetails.getUsername()));
    }

    /** PUT /api/v1/posts/{id} */
    @PutMapping("/{id}")
    public ResponseEntity<PostDetailResponse> update(
            @PathVariable Long id,
            @Valid @RequestBody UpdatePostRequest request,
            @AuthenticationPrincipal UserDetails userDetails) {
        return ResponseEntity.ok(postService.update(id, request, userDetails.getUsername()));
    }

    /** DELETE /api/v1/posts/{id} */
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(
            @PathVariable Long id,
            @AuthenticationPrincipal UserDetails userDetails) {
        postService.delete(id, userDetails.getUsername());
        return ResponseEntity.noContent().build();
    }

    // ── Util ──────────────────────────────────────────────────────────────────

    private Pageable buildPageable(int page, int size, String sortParam) {
        if (page < 0 || size < 1) throw new InvalidRequestException("Invalid pagination");
        String[] parts = sortParam.split(",", -1);
        if (parts.length > 2 || !SORT_PROPERTIES.contains(parts[0])) {
            throw new InvalidRequestException("Unsupported sort property");
        }
        if (parts.length == 2 && !parts[1].equalsIgnoreCase("asc") && !parts[1].equalsIgnoreCase("desc")) {
            throw new InvalidRequestException("Unsupported sort direction");
        }
        Sort.Direction direction = parts.length > 1 && parts[1].equalsIgnoreCase("asc")
                ? Sort.Direction.ASC : Sort.Direction.DESC;
        return PageRequest.of(page, Math.min(size, 50), Sort.by(direction, parts[0]));
    }
}
