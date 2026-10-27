package com.blogapi.controller;

import com.blogapi.dto.request.PostRequests.UpdatePostRequest;
import com.blogapi.dto.response.Responses.PostDetailResponse;
import com.blogapi.service.PostService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;

/**
 * Bản VÁ của các thao tác trên bài viết, làm cặp đối chứng với {@code /api/v1/vuln/posts} (chỉ có trong lab).
 * Dùng chung {@link PostService} với các route bài viết thường, nên thừa hưởng nguyên kiểm tra chủ sở hữu
 * (Ownership Check) ở tầng Service và phản hồi không chứa email tác giả.
 */
@RestController
@RequestMapping("/api/v1/secure/posts")
@RequiredArgsConstructor
public class SecurePostController {

    private final PostService postService;

    /** Chủ sở hữu hoặc ADMIN đọc được mọi trạng thái; người khác đọc bản nháp -> 403. */
    @GetMapping("/{id}")
    public ResponseEntity<PostDetailResponse> getById(
            @PathVariable Long id,
            @AuthenticationPrincipal UserDetails userDetails) {
        return ResponseEntity.ok(postService.getById(id, userDetails.getUsername()));
    }

    /** Chỉ chủ sở hữu hoặc ADMIN được sửa; người khác -> 403. */
    @PutMapping("/{id}")
    public ResponseEntity<PostDetailResponse> update(
            @PathVariable Long id,
            @Valid @RequestBody UpdatePostRequest request,
            @AuthenticationPrincipal UserDetails userDetails) {
        return ResponseEntity.ok(postService.update(id, request, userDetails.getUsername()));
    }

    /** Chỉ chủ sở hữu hoặc ADMIN được xóa; người khác -> 403. */
    @DeleteMapping("/{id}")
    public ResponseEntity<Void> delete(
            @PathVariable Long id,
            @AuthenticationPrincipal UserDetails userDetails) {
        postService.delete(id, userDetails.getUsername());
        return ResponseEntity.noContent().build();
    }
}
