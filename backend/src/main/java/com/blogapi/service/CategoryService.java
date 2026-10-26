package com.blogapi.service;

import com.blogapi.dto.request.CategoryRequests.*;
import com.blogapi.dto.response.Responses.CategoryResponse;

import java.util.List;

public interface CategoryService {
    CategoryResponse create(CreateCategoryRequest request);
    CategoryResponse update(Long id, UpdateCategoryRequest request);
    void delete(Long id);
    CategoryResponse getById(Long id);
    CategoryResponse getBySlug(String slug);
    List<CategoryResponse> getAll();
}
