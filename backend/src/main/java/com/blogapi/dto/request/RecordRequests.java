package com.blogapi.dto.request;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Size;

public final class RecordRequests {
    private RecordRequests() {}

    public record CreateRecordRequest(@NotBlank String content) {}

    public record SearchRecordRequest(@NotBlank @Size(max = 200) String keyword) {}
}
