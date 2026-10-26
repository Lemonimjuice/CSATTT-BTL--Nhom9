package com.blogapi.repository;

import com.blogapi.entity.Comment;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.List;

@Repository
public interface CommentRepository extends JpaRepository<Comment, Long> {

    /** Top-level comments for a post (no parent) */
    @Query("SELECT c FROM Comment c WHERE c.post.id = :postId AND c.parent IS NULL ORDER BY c.createdAt ASC")
    Page<Comment> findTopLevelByPostId(@Param("postId") Long postId, Pageable pageable);

    /** Direct replies to a specific comment */
    List<Comment> findByParentIdOrderByCreatedAtAsc(Long parentId);

    long countByPostIdAndDeletedFalse(Long postId);
}
