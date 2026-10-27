package com.blogapi.security;

import com.blogapi.entity.Post;
import com.blogapi.entity.User;
import com.blogapi.exception.ForbiddenException;
import com.blogapi.exception.UnauthenticatedException;
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
        // Anonymous callers get 401 (log in first), known non-owners get 403: the original app answered 403 to both.
        if (username == null) throw new UnauthenticatedException("Authentication is required to read this post");
        boolean owner = post.getAuthor().getUsername().equals(username);
        boolean admin = userRepository.findByUsername(username)
                .map(user -> user.getRole() == User.Role.ADMIN).orElse(false);
        if (!owner && !admin) throw new ForbiddenException("You do not have permission to read this post");
    }
}
