package com.blogapi.service.impl;

import com.blogapi.dto.request.PostRequests.*;
import com.blogapi.dto.response.Responses.*;
import com.blogapi.entity.Category;
import com.blogapi.entity.Post;
import com.blogapi.entity.Post.Status;
import com.blogapi.entity.User;
import com.blogapi.exception.DuplicateResourceException;
import com.blogapi.exception.ForbiddenException;
import com.blogapi.exception.ResourceNotFoundException;
import com.blogapi.repository.CategoryRepository;
import com.blogapi.repository.PostRepository;
import com.blogapi.repository.UserRepository;
import com.blogapi.service.PostService;
import com.blogapi.util.EntityMapper;
import com.blogapi.util.SlugUtils;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
@RequiredArgsConstructor
@Slf4j
public class PostServiceImpl implements PostService {

    private final PostRepository     postRepository;
    private final UserRepository     userRepository;
    private final CategoryRepository categoryRepository;

    @Override
    @Transactional
    public PostDetailResponse create(CreatePostRequest request, String username) {
        User author = findUserOrThrow(username);

        String slug = ensureUniqueSlug(SlugUtils.toSlug(request.title()));

        Category category = null;
        if (request.categoryId() != null) {
            category = categoryRepository.findById(request.categoryId())
                    .orElseThrow(() -> new ResourceNotFoundException("Category", request.categoryId()));
        }

        Post post = Post.builder()
                .title(request.title())
                .slug(slug)
                .content(request.content())
                .summary(request.summary())
                .status(request.status() != null ? request.status() : Status.DRAFT)
                .author(author)
                .category(category)
                .build();

        post = postRepository.save(post);
        log.info("Post created: id={}, slug={}, author={}", post.getId(), post.getSlug(), username);
        return EntityMapper.toPostDetail(post);
    }

    @Override
    @Transactional
    public PostDetailResponse update(Long id, UpdatePostRequest request, String username) {
        Post post = findPostOrThrow(id);
        assertOwnerOrAdmin(post, username);

        if (request.title() != null && !request.title().isBlank()) {
            String newSlug = SlugUtils.toSlug(request.title());
            if (!post.getSlug().equals(newSlug)) {
                post.setSlug(ensureUniqueSlug(newSlug));
            }
            post.setTitle(request.title());
        }
        if (request.content() != null)  post.setContent(request.content());
        if (request.summary() != null)  post.setSummary(request.summary());
        if (request.status()  != null)  post.setStatus(request.status());

        if (request.categoryId() != null) {
            Category cat = categoryRepository.findById(request.categoryId())
                    .orElseThrow(() -> new ResourceNotFoundException("Category", request.categoryId()));
            post.setCategory(cat);
        }

        log.info("Post updated: id={}, updatedBy={}", id, username);
        return EntityMapper.toPostDetail(postRepository.save(post));
    }

    @Override
    @Transactional
    public void delete(Long id, String username) {
        Post post = findPostOrThrow(id);
        assertOwnerOrAdmin(post, username);
        postRepository.delete(post);
        log.info("Post deleted: id={}, deletedBy={}", id, username);
    }

    @Override
    @Transactional(readOnly = true)
    public PostDetailResponse getById(Long id, String requesterUsername) {
        Post post = findPostOrThrow(id);
        assertCanRead(post, requesterUsername);
        return EntityMapper.toPostDetail(post);
    }

    @Override
    @Transactional(readOnly = true)
    public PostDetailResponse getBySlug(String slug, String requesterUsername) {
        Post post = postRepository.findBySlug(slug)
                .orElseThrow(() -> new ResourceNotFoundException("Post", "slug", slug));
        assertCanRead(post, requesterUsername);
        return EntityMapper.toPostDetail(post);
    }

    @Override
    @Transactional(readOnly = true)
    public PageResponse<PostSummaryResponse> getPublished(Pageable pageable) {
        return toPageResponse(postRepository.findAllByStatus(Status.PUBLISHED, pageable));
    }

    @Override
    @Transactional(readOnly = true)
    public PageResponse<PostSummaryResponse> getByCategory(Long categoryId, Pageable pageable) {
        return toPageResponse(postRepository.findAllByCategoryIdAndStatus(categoryId, Status.PUBLISHED, pageable));
    }

    @Override
    @Transactional(readOnly = true)
    public PageResponse<PostSummaryResponse> getByAuthor(Long authorId, Pageable pageable) {
        return toPageResponse(postRepository.findAllByAuthorIdAndStatus(authorId, Status.PUBLISHED, pageable));
    }

    @Override
    @Transactional(readOnly = true)
    public PageResponse<PostSummaryResponse> search(String keyword, Pageable pageable) {
        return toPageResponse(postRepository.searchByKeyword(keyword, Status.PUBLISHED, pageable));
    }

    @Override
    @Transactional(readOnly = true)
    public PageResponse<PostSummaryResponse> getMyPosts(String username, Pageable pageable) {
        User author = findUserOrThrow(username);
        Page<Post> page = postRepository.findAll(pageable); // all statuses for own posts
        // Filter by author in memory since we need all statuses
        return toPageResponse(postRepository.findAllByAuthorIdAndStatus(author.getId(), Status.PUBLISHED, pageable));
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    private Post findPostOrThrow(Long id) {
        return postRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Post", id));
    }

    private User findUserOrThrow(String username) {
        return userRepository.findByUsername(username)
                .orElseThrow(() -> new ResourceNotFoundException("User", "username", username));
    }

    private void assertOwnerOrAdmin(Post post, String username) {
        boolean isOwner = post.getAuthor().getUsername().equals(username);
        boolean isAdmin = userRepository.findByUsername(username)
                .map(u -> u.getRole() == com.blogapi.entity.User.Role.ADMIN)
                .orElse(false);
        if (!isOwner && !isAdmin)
            throw new ForbiddenException("You do not have permission to modify this post");
    }

    private void assertCanRead(Post post, String username) {
        if (post.getStatus() == Status.PUBLISHED) return;
        if (username == null) throw new ForbiddenException("You do not have permission to read this post");
        assertOwnerOrAdmin(post, username);
    }

    private String ensureUniqueSlug(String base) {
        if (!postRepository.existsBySlug(base)) return base;
        int suffix = 1;
        String candidate;
        do { candidate = base + "-" + suffix++; }
        while (postRepository.existsBySlug(candidate));
        return candidate;
    }

    private PageResponse<PostSummaryResponse> toPageResponse(Page<Post> page) {
        return new PageResponse<>(
                page.getContent().stream().map(EntityMapper::toPostSummary).toList(),
                page.getNumber(),
                page.getSize(),
                page.getTotalElements(),
                page.getTotalPages(),
                page.isLast()
        );
    }
}
