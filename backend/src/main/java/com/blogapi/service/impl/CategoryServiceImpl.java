package com.blogapi.service.impl;

import com.blogapi.dto.request.CategoryRequests.*;
import com.blogapi.dto.response.Responses.CategoryResponse;
import com.blogapi.entity.Category;
import com.blogapi.exception.DuplicateResourceException;
import com.blogapi.exception.ResourceNotFoundException;
import com.blogapi.repository.CategoryRepository;
import com.blogapi.service.CategoryService;
import com.blogapi.util.EntityMapper;
import com.blogapi.util.SlugUtils;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Service
@RequiredArgsConstructor
@Slf4j
public class CategoryServiceImpl implements CategoryService {

    private final CategoryRepository categoryRepository;

    @Override
    @Transactional
    public CategoryResponse create(CreateCategoryRequest request) {
        if (categoryRepository.existsByName(request.name()))
            throw new DuplicateResourceException("Category already exists: " + request.name());

        String slug = SlugUtils.toSlug(request.name());
        if (categoryRepository.existsBySlug(slug))
            throw new DuplicateResourceException("Category slug conflict: " + slug);

        Category category = Category.builder()
                .name(request.name())
                .slug(slug)
                .description(request.description())
                .build();

        category = categoryRepository.save(category);
        log.info("Category created: {} (slug={})", category.getName(), category.getSlug());
        return EntityMapper.toCategoryResponse(category);
    }

    @Override
    @Transactional
    public CategoryResponse update(Long id, UpdateCategoryRequest request) {
        Category category = findOrThrow(id);

        if (request.name() != null && !request.name().isBlank()) {
            if (!category.getName().equals(request.name()) && categoryRepository.existsByName(request.name()))
                throw new DuplicateResourceException("Category name already in use: " + request.name());
            category.setName(request.name());
            category.setSlug(SlugUtils.toSlug(request.name()));
        }
        if (request.description() != null) {
            category.setDescription(request.description());
        }

        log.info("Category updated: id={}", id);
        return EntityMapper.toCategoryResponse(categoryRepository.save(category));
    }

    @Override
    @Transactional
    public void delete(Long id) {
        Category category = findOrThrow(id);
        categoryRepository.delete(category);
        log.info("Category deleted: id={}", id);
    }

    @Override
    @Transactional(readOnly = true)
    public CategoryResponse getById(Long id) {
        return EntityMapper.toCategoryResponse(findOrThrow(id));
    }

    @Override
    @Transactional(readOnly = true)
    public CategoryResponse getBySlug(String slug) {
        return categoryRepository.findBySlug(slug)
                .map(EntityMapper::toCategoryResponse)
                .orElseThrow(() -> new ResourceNotFoundException("Category", "slug", slug));
    }

    @Override
    @Transactional(readOnly = true)
    public List<CategoryResponse> getAll() {
        return categoryRepository.findAll().stream()
                .map(EntityMapper::toCategoryResponse)
                .toList();
    }

    private Category findOrThrow(Long id) {
        return categoryRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Category", id));
    }
}
