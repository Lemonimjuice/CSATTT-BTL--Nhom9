package com.blogapi.service;

import com.blogapi.dto.request.PostRequests.*;
import com.blogapi.dto.response.Responses.*;
import org.springframework.data.domain.Pageable;

public interface PostService {
    PostDetailResponse  create(CreatePostRequest request, String username);
    PostDetailResponse  update(Long id, UpdatePostRequest request, String username);
    void                delete(Long id, String username);
    PostDetailResponse  getById(Long id, String requesterUsername);
    PostDetailResponse  getBySlug(String slug, String requesterUsername);
    PageResponse<PostSummaryResponse> getPublished(Pageable pageable);
    PageResponse<PostSummaryResponse> getByCategory(Long categoryId, Pageable pageable);
    PageResponse<PostSummaryResponse> getByAuthor(Long authorId, Pageable pageable);
    PageResponse<PostSummaryResponse> search(String keyword, Pageable pageable);
    PageResponse<PostSummaryResponse> getMyPosts(String username, Pageable pageable);
}
