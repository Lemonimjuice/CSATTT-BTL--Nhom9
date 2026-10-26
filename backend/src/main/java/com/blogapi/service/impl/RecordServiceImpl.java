package com.blogapi.service.impl;

import com.blogapi.dto.request.RecordRequests.CreateRecordRequest;
import com.blogapi.dto.response.RecordResponse;
import com.blogapi.entity.Record;
import com.blogapi.entity.User;
import com.blogapi.exception.ForbiddenException;
import com.blogapi.exception.ResourceNotFoundException;
import com.blogapi.repository.RecordRepository;
import com.blogapi.repository.UserRepository;
import com.blogapi.service.RecordService;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.data.domain.PageRequest;

import java.util.List;

@Service
@RequiredArgsConstructor
public class RecordServiceImpl implements RecordService {

    private final RecordRepository recordRepository;
    private final UserRepository userRepository;

    @Override
    @Transactional
    public RecordResponse create(CreateRecordRequest request, String username) {
        User owner = userRepository.findByUsername(username)
                .orElseThrow(() -> new ResourceNotFoundException("User", "username", username));
        Record saved = recordRepository.save(Record.builder()
                .content(request.content())
                .owner(owner)
                .build());
        return toResponse(saved);
    }

    @Override
    @Transactional(readOnly = true)
    public RecordResponse getById(Long id, String username) {
        Record record = recordRepository.findById(id)
                .orElseThrow(() -> new ResourceNotFoundException("Record", id));
        if (!record.getOwner().getUsername().equals(username)) {
            throw new ForbiddenException("You do not have permission to read this record");
        }
        return toResponse(record);
    }

    @Override
    @Transactional(readOnly = true)
    public List<RecordResponse> search(String keyword, String username) {
        // Both the authenticated owner and the literal search text are bound parameters.
        return recordRepository.searchOwned(username, keyword, PageRequest.of(0, 50))
                .stream().map(this::toResponse).toList();
    }

    private RecordResponse toResponse(Record record) {
        return new RecordResponse(record.getId(), record.getContent());
    }
}
