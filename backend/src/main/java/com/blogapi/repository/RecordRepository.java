package com.blogapi.repository;

import com.blogapi.entity.Record;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.data.domain.Pageable;

import java.util.List;

public interface RecordRepository extends JpaRepository<Record, Long> {

    @Query("SELECT r FROM Record r WHERE r.owner.username = :username " +
           "AND LOCATE(LOWER(:keyword), LOWER(r.content)) > 0 ORDER BY r.id")
    List<Record> searchOwned(@Param("username") String username,
                             @Param("keyword") String keyword, Pageable pageable);
}
