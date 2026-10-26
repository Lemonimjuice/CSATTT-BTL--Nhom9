package com.blogapi.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public class CommentRequests {

    public record CreateCommentRequest(
            @NotBlank(message = "Content is required")
            @Size(max = 2000, message = "Comment must not exceed 2000 characters")
            String content,

            /** Null for top-level comment; set to parent comment id for a reply */
            Long parentId
    ) {}

    public record UpdateCommentRequest(
            @NotBlank(message = "Content is required")
            @Size(max = 2000, message = "Comment must not exceed 2000 characters")
            String content
    ) {}
}
