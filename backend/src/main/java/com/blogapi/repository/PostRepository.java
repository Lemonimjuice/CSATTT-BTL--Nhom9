package com.blogapi.repository;

import com.blogapi.entity.Post;
import com.blogapi.entity.Post.Status;
import org.springframework.data.domain.Page;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;
import org.springframework.stereotype.Repository;

import java.util.Optional;

@Repository
public interface PostRepository extends JpaRepository<Post, Long> {

    Optional<Post> findBySlug(String slug);

    boolean existsBySlug(String slug);

    Page<Post> findAllByStatus(Status status, Pageable pageable);

    Page<Post> findAllByCategoryIdAndStatus(Long categoryId, Status status, Pageable pageable);

    Page<Post> findAllByAuthorIdAndStatus(Long authorId, Status status, Pageable pageable);

    @Query("SELECT p FROM Post p WHERE p.status = :status AND " +
           "(LOWER(p.title) LIKE LOWER(CONCAT('%', :keyword, '%')) OR " +
           "LOWER(p.content) LIKE LOWER(CONCAT('%', :keyword, '%')))")
    Page<Post> searchByKeyword(@Param("keyword") String keyword,
                               @Param("status") Status status,
                               Pageable pageable);
}
