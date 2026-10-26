package com.blogapi.dto.request;

import com.blogapi.entity.Post.Status;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;
import jakarta.validation.constraints.Size;

public class PostRequests {

    public record CreatePostRequest(
            @NotBlank(message = "Title is required")
            @Size(max = 255, message = "Title must not exceed 255 characters")
            String title,

            @NotBlank(message = "Content is required")
            String content,

            @Size(max = 500, message = "Summary must not exceed 500 characters")
            String summary,

            Long categoryId,

            Status status
    ) {}

    public record UpdatePostRequest(
            @Size(max = 255, message = "Title must not exceed 255 characters")
            String title,

            String content,

            @Size(max = 500, message = "Summary must not exceed 500 characters")
            String summary,

            Long categoryId,

            Status status
    ) {}
}
