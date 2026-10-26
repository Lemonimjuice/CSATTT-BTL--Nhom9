package com.blogapi.service;

import com.blogapi.dto.request.CommentRequests.*;
import com.blogapi.dto.response.Responses.*;
import org.springframework.data.domain.Pageable;

public interface CommentService {
    CommentResponse create(Long postId, CreateCommentRequest request, String username);
    CommentResponse update(Long commentId, UpdateCommentRequest request, String username);
    void delete(Long commentId, String username);
    PageResponse<CommentResponse> getByPost(Long postId, Pageable pageable);
    CommentResponse getById(Long commentId);
}
