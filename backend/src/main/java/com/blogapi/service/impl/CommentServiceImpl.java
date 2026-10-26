package com.blogapi.service.impl;

import com.blogapi.dto.request.CommentRequests.*;
import com.blogapi.dto.response.Responses.*;
import com.blogapi.entity.Comment;
import com.blogapi.entity.Post;
import com.blogapi.entity.User;
import com.blogapi.exception.ForbiddenException;
import com.blogapi.exception.ResourceNotFoundException;
import com.blogapi.repository.CommentRepository;
import com.blogapi.repository.PostRepository;
import com.blogapi.repository.UserRepository;
import com.blogapi.service.CommentService;
import com.blogapi.security.PostReadAccessPolicy;
import com.blogapi.util.EntityMapper;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
@Slf4j
public class CommentServiceImpl implements CommentService {

    private static final int MAX_DEPTH = 5;

    private final CommentRepository commentRepository;
    private final PostRepository    postRepository;
    private final UserRepository    userRepository;
    private final PostReadAccessPolicy postReadAccessPolicy;

    // ── Create ────────────────────────────────────────────────────────────────

    @Override
    @Transactional
    public CommentResponse create(Long postId, CreateCommentRequest request, String username) {
        Post post   = findPostOrThrow(postId);
        postReadAccessPolicy.assertCanRead(post, username);
        User author = findUserOrThrow(username);

        Comment parent = null;
        int depth = 0;

        if (request.parentId() != null) {
            parent = findCommentOrThrow(request.parentId());

            // Ensure the parent belongs to the same post
            if (!parent.getPost().getId().equals(postId)) {
                throw new IllegalArgumentException("Parent comment does not belong to this post");
            }
            // Enforce depth cap to prevent infinite nesting
            depth = parent.getDepth() + 1;
            if (depth > MAX_DEPTH) {
                throw new IllegalArgumentException(
                        "Maximum comment nesting depth (%d) reached".formatted(MAX_DEPTH));
            }
        }

        Comment comment = Comment.builder()
                .content(request.content())
                .post(post)
                .author(author)
                .parent(parent)
                .depth(depth)
                .build();

        comment = commentRepository.save(comment);
        log.info("Comment created: id={}, postId={}, depth={}, author={}",
                comment.getId(), postId, depth, username);

        return EntityMapper.toCommentResponse(comment);
    }

    // ── Update ────────────────────────────────────────────────────────────────

    @Override
    @Transactional
    public CommentResponse update(Long commentId, UpdateCommentRequest request, String username) {
        Comment comment = findCommentOrThrow(commentId);
        assertOwnerOrModerator(comment, username);

        comment.setContent(request.content());
        log.info("Comment updated: id={}, updatedBy={}", commentId, username);
        return EntityMapper.toCommentResponse(commentRepository.save(comment));
    }

    // ── Soft Delete ───────────────────────────────────────────────────────────

    @Override
    @Transactional
    public void delete(Long commentId, String username) {
        Comment comment = findCommentOrThrow(commentId);
        assertOwnerOrModerator(comment, username);

        // Soft-delete: keeps the thread structure intact for nested replies
        comment.setDeleted(true);
        comment.setContent("[deleted]");
        commentRepository.save(comment);
        log.info("Comment soft-deleted: id={}, deletedBy={}", commentId, username);
    }

    // ── Read ──────────────────────────────────────────────────────────────────

    /**
     * Returns paginated top-level comments for a post.
     * Each comment already carries its full nested reply tree because
     * {@link EntityMapper#toCommentResponse} recurses into {@code replies}.
     */
    @Override
    @Transactional(readOnly = true)
    public PageResponse<CommentResponse> getByPost(Long postId, Pageable pageable, String requesterUsername) {
        postReadAccessPolicy.assertCanRead(findPostOrThrow(postId), requesterUsername);
        Page<Comment> topLevel = commentRepository.findTopLevelByPostId(postId, pageable);

        List<CommentResponse> responses = topLevel.getContent().stream()
                .map(this::loadRepliesAndMap)
                .toList();

        return new PageResponse<>(
                responses,
                topLevel.getNumber(),
                topLevel.getSize(),
                topLevel.getTotalElements(),
                topLevel.getTotalPages(),
                topLevel.isLast()
        );
    }

    @Override
    @Transactional(readOnly = true)
    public CommentResponse getById(Long commentId, String requesterUsername) {
        Comment comment = findCommentOrThrow(commentId);
        postReadAccessPolicy.assertCanRead(comment.getPost(), requesterUsername);
        return loadRepliesAndMap(comment);
    }

    // ── Helpers ───────────────────────────────────────────────────────────────

    /**
     * Eagerly loads the full reply subtree for a comment and maps it.
     * Uses the DB to fetch each level's direct children rather than
     * relying on lazy-loaded collections, giving clean N-per-level queries.
     */
    private CommentResponse loadRepliesAndMap(Comment comment) {
        populateReplies(comment);
        return EntityMapper.toCommentResponse(comment);
    }

    private void populateReplies(Comment comment) {
        List<Comment> directReplies =
                commentRepository.findByParentIdOrderByCreatedAtAsc(comment.getId());
        comment.setReplies(directReplies);
        // Recurse into each reply
        for (Comment reply : directReplies) {
            populateReplies(reply);
        }
    }

    private void assertOwnerOrModerator(Comment comment, String username) {
        boolean isOwner     = comment.getAuthor().getUsername().equals(username);
        boolean isModerator = userRepository.findByUsername(username)
                .map(u -> u.getRole() == com.blogapi.entity.User.Role.MODERATOR
                       || u.getRole() == com.blogapi.entity.User.Role.ADMIN)
                .orElse(false);
        if (!isOwner && !isModerator)
            throw new ForbiddenException("You do not have permission to modify this comment");
    }

    private Post findPostOrThrow(Long id) {
        return postRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Post", id));
    }

    private User findUserOrThrow(String username) {
        return userRepository.findByUsername(username)
                .orElseThrow(() -> new ResourceNotFoundException("User", "username", username));
    }

    private Comment findCommentOrThrow(Long id) {
        return commentRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Comment", id));
    }
}
