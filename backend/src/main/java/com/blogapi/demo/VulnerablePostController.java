package com.blogapi.demo;

import com.blogapi.dto.response.Responses.UserSummary;
import com.blogapi.entity.Post;
import com.blogapi.exception.ResourceNotFoundException;
import com.blogapi.repository.PostRepository;
import com.blogapi.util.EntityMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.bind.annotation.*;

/**
 * Deliberately vulnerable copies of the original Post endpoints, for the comparison demos only.
 * Same conditions as the SQLi lab: they exist only in the isolated lab API (own identity DB and JWT key).
 * Secure counterparts on the main backend: GET/PUT/DELETE /api/v1/posts/{id}.
 */
@RestController
@RequestMapping("/api/v1/vuln/posts")
@RequiredArgsConstructor
@Slf4j
@Profile("sqli-lab")
@ConditionalOnProperty(prefix = "app.demo.sqli", name = "enabled", havingValue = "true")
public class VulnerablePostController {

    private final PostRepository postRepository;

    /** Original weaknesses: any caller reads DRAFT/ARCHIVED posts by ID, and the author's email is returned. */
    @GetMapping("/{id}")
    @Transactional(readOnly = true)
    public VulnerablePostResponse getById(@PathVariable Long id) {
        return toResponse(findOrThrow(id));
    }

    /** IDOR: no ownership check, any authenticated user edits any post. */
    @PutMapping("/{id}")
    @Transactional
    public VulnerablePostResponse update(@PathVariable Long id,
                                         @RequestBody VulnerablePostUpdate request,
                                         @AuthenticationPrincipal UserDetails userDetails) {
        Post post = findOrThrow(id);
        if (request.title() != null) post.setTitle(request.title());
        if (request.content() != null) post.setContent(request.content());
        log.warn("VULN post updated without ownership check: id={}, by={}", id, userDetails.getUsername());
        return toResponse(postRepository.save(post));
    }

    /** IDOR: no ownership check, any authenticated user deletes any post. */
    @DeleteMapping("/{id}")
    @Transactional
    public ResponseEntity<Void> delete(@PathVariable Long id, @AuthenticationPrincipal UserDetails userDetails) {
        postRepository.delete(findOrThrow(id));
        log.warn("VULN post deleted without ownership check: id={}, by={}", id, userDetails.getUsername());
        return ResponseEntity.noContent().build();
    }

    private Post findOrThrow(Long id) {
        return postRepository.findById(id).orElseThrow(() -> new ResourceNotFoundException("Post", id));
    }

    private static VulnerablePostResponse toResponse(Post post) {
        return new VulnerablePostResponse(post.getId(), post.getTitle(), post.getContent(),
                post.getStatus(), EntityMapper.toUserSummary(post.getAuthor()));
    }

    public record VulnerablePostUpdate(String title, String content) {}

    public record VulnerablePostResponse(Long id, String title, String content,
                                         Post.Status status, UserSummary author) {}
}
