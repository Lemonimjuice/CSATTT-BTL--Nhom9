package com.blogapi.controller;

import com.blogapi.dto.request.RecordRequests.CreateRecordRequest;
import com.blogapi.dto.request.RecordRequests.SearchRecordRequest;
import com.blogapi.dto.response.RecordResponse;
import com.blogapi.service.RecordService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.core.userdetails.UserDetails;
import org.springframework.web.bind.annotation.*;

import java.util.List;

@RestController
@RequestMapping("/api/v1/secure/records")
@RequiredArgsConstructor
public class RecordController {

    private final RecordService recordService;

    @PostMapping
    public ResponseEntity<RecordResponse> create(
            @Valid @RequestBody CreateRecordRequest request,
            @AuthenticationPrincipal UserDetails userDetails) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(recordService.create(request, userDetails.getUsername()));
    }

    @GetMapping("/{id}")
    public ResponseEntity<RecordResponse> getById(
            @PathVariable Long id,
            @AuthenticationPrincipal UserDetails userDetails) {
        return ResponseEntity.ok(recordService.getById(id, userDetails.getUsername()));
    }

    @PostMapping("/search")
    public ResponseEntity<List<RecordResponse>> search(
            @Valid @RequestBody SearchRecordRequest request,
            @AuthenticationPrincipal UserDetails userDetails) {
        return ResponseEntity.ok(recordService.search(request.keyword(), userDetails.getUsername()));
    }
}
