package com.blogapi.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public class CategoryRequests {

    public record CreateCategoryRequest(
            @NotBlank(message = "Name is required")
            @Size(max = 100, message = "Name must not exceed 100 characters")
            String name,

            @Size(max = 500, message = "Description must not exceed 500 characters")
            String description
    ) {}

    public record UpdateCategoryRequest(
            @Size(max = 100, message = "Name must not exceed 100 characters")
            String name,

            @Size(max = 500, message = "Description must not exceed 500 characters")
            String description
    ) {}
}
