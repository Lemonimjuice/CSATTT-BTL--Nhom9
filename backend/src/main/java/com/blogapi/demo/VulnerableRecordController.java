package com.blogapi.demo;

import com.blogapi.dto.request.RecordRequests.SearchRecordRequest;
import com.blogapi.dto.response.RecordResponse;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.context.annotation.Profile;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/v1/vuln/records")
@RequiredArgsConstructor
@Profile("sqli-lab")
@ConditionalOnProperty(prefix = "app.demo.sqli", name = "enabled", havingValue = "true")
public class VulnerableRecordController {

    private final SqliLabRepository repository;

    @PostMapping("/search")
    public List<RecordResponse> search(@Valid @RequestBody SearchRecordRequest request) {
        return repository.search(request.keyword());
    }

    @ExceptionHandler(SqliLabRepository.LabQueryException.class)
    public ResponseEntity<Map<String, Object>> rejectedQuery() {
        return ResponseEntity.badRequest().body(Map.of("status", 400, "message", "Demo query rejected"));
    }

    @ExceptionHandler(SqliLabRepository.LabUnavailableException.class)
    public ResponseEntity<Map<String, Object>> unavailableLab() {
        return ResponseEntity.status(503).body(Map.of("status", 503, "message", "SQLi lab isolation check failed"));
    }
}
