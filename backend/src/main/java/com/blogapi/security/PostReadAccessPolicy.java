package com.blogapi.security;

import com.blogapi.entity.Post;
import com.blogapi.entity.User;
import com.blogapi.exception.ForbiddenException;
import com.blogapi.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Component;

/** The same Post visibility check is used before exposing or creating its comments. */
@Component
@RequiredArgsConstructor
public class PostReadAccessPolicy {
    private final UserRepository userRepository;

    public void assertCanRead(Post post, String username) {
        if (post.getStatus() == Post.Status.PUBLISHED) return;
        if (username == null) throw new ForbiddenException("You do not have permission to read this post");
        boolean owner = post.getAuthor().getUsername().equals(username);
        boolean admin = userRepository.findByUsername(username)
                .map(user -> user.getRole() == User.Role.ADMIN).orElse(false);
        // Retain the existing Post response message as well as its owner/ADMIN policy.
        if (!owner && !admin) throw new ForbiddenException("You do not have permission to modify this post");
    }
}
