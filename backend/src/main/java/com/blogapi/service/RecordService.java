package com.blogapi.service;

import com.blogapi.dto.request.RecordRequests.CreateRecordRequest;
import com.blogapi.dto.response.RecordResponse;

import java.util.List;

public interface RecordService {
    RecordResponse create(CreateRecordRequest request, String username);
    RecordResponse getById(Long id, String username);
    List<RecordResponse> search(String keyword, String username);
}
