package com.blogapi;

import com.blogapi.entity.Comment;
import com.blogapi.entity.Post;
import com.blogapi.entity.User;
import com.blogapi.repository.CommentRepository;
import com.blogapi.repository.PostRepository;
import com.blogapi.repository.UserRepository;
import com.blogapi.security.JwtService;
import com.blogapi.security.UserDetailsServiceImpl;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.Arguments;
import org.junit.jupiter.params.provider.MethodSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.MockMvcPrint;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.util.HashMap;
import java.util.Map;
import java.util.stream.Stream;

import static org.assertj.core.api.Assertions.assertThat;
import static org.hamcrest.Matchers.containsString;
import static org.hamcrest.Matchers.not;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc(print = MockMvcPrint.NONE)
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:commentaccess;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa", "spring.datasource.password=",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.jpa.hibernate.ddl-auto=create-drop", "spring.jpa.show-sql=false",
        "spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.H2Dialect",
        "app.jwt.secret=cmVjb3JkLWFwaS10ZXN0LXNpZ25pbmcta2V5LWF0LWxlYXN0LTMyLWJ5dGVzLWxvbmc=",
        "logging.level.org.hibernate.SQL=OFF"
})
class CommentPostAccessIntegrationTest {
    @Autowired MockMvc http;
    @Autowired UserRepository users;
    @Autowired PostRepository posts;
    @Autowired CommentRepository comments;
    @Autowired JwtService jwt;
    @Autowired UserDetailsServiceImpl userDetails;
    private final Map<String, String> tokens = new HashMap<>();
    private User owner;

    @BeforeAll
    void createActors() {
        for (String actor : new String[]{"owner", "other", "admin", "moderator"}) {
            User user = users.save(User.builder().username("comment-" + actor)
                    .email(actor + "@comment.example.test").password("unused-jwt-only-test-fixture")
                    .role(actor.equals("admin") ? User.Role.ADMIN
                            : actor.equals("moderator") ? User.Role.MODERATOR : User.Role.USER)
                    .enabled(true).build());
            if (actor.equals("owner")) owner = user;
            tokens.put(actor, jwt.generateAccessToken(userDetails.loadUserByUsername(user.getUsername())));
        }
    }

    @BeforeEach
    void clearPosts() {
        comments.deleteAll();
        posts.deleteAll();
    }

    static Stream<Arguments> accessCases() {
        return Stream.of(Post.Status.values()).flatMap(state ->
                Stream.of("anonymous", "owner", "other", "admin", "moderator")
                        .map(actor -> Arguments.of(state, actor)));
    }

    @ParameterizedTest(name = "list {0} as {1}")
    @MethodSource("accessCases")
    void listingCommentsUsesPostReadPolicy(Post.Status state, String actor) throws Exception {
        Post post = savePost(state);
        Comment root = saveComment(post, null);
        saveComment(post, root);
        boolean allowed = mayRead(state, actor);
        http.perform(as(actor, get("/api/v1/posts/{id}", post.getId())))
                .andExpect(status().is(allowed ? 200 : 403));
        http.perform(as(actor, get("/api/v1/posts/{id}/comments", post.getId())))
                .andExpect(status().is(allowed ? 200 : 403))
                .andExpect(content().string(allowed ? containsString("comment-content-fixture")
                        : not(containsString("comment-content-fixture"))));
    }

    @ParameterizedTest(name = "single/reply {0} as {1}")
    @MethodSource("accessCases")
    void readingCommentAndReplyUsesPostReadPolicy(Post.Status state, String actor) throws Exception {
        Post post = savePost(state);
        Comment root = saveComment(post, null);
        Comment reply = saveComment(post, root);
        boolean allowed = mayRead(state, actor);
        for (Comment comment : new Comment[]{root, reply}) {
            http.perform(as(actor, get("/api/v1/comments/{id}", comment.getId())))
                    .andExpect(status().is(allowed ? 200 : 403))
                    .andExpect(content().string(allowed ? containsString("comment-content-fixture")
                            : not(containsString("comment-content-fixture"))));
        }
    }

    @ParameterizedTest(name = "create/reply {0} as {1}")
    @MethodSource("accessCases")
    void creatingCommentAndReplyRequiresAccessToPost(Post.Status state, String actor) throws Exception {
        Post post = savePost(state);
        Comment root = saveComment(post, null);
        long before = comments.count();
        boolean allowed = !actor.equals("anonymous") && mayRead(state, actor);
        for (String body : new String[]{"{\"content\":\"new comment fixture\"}",
                "{\"content\":\"new reply fixture\",\"parentId\":" + root.getId() + "}"}) {
            http.perform(as(actor, post("/api/v1/posts/{id}/comments", post.getId()))
                            .contentType(MediaType.APPLICATION_JSON).content(body))
                    .andExpect(status().is(allowed ? 201 : actor.equals("anonymous") ? 401 : 403));
        }
        assertThat(comments.count() - before).isEqualTo(allowed ? 2 : 0);
    }

    @Test
    void commentsBecomePrivateWhenPublishedPostBecomesDraftOrArchived() throws Exception {
        Post post = savePost(Post.Status.PUBLISHED);
        Comment comment = saveComment(post, null);
        http.perform(get("/api/v1/comments/{id}", comment.getId())).andExpect(status().isOk());
        for (Post.Status state : new Post.Status[]{Post.Status.DRAFT, Post.Status.ARCHIVED}) {
            post.setStatus(state);
            posts.save(post);
            http.perform(get("/api/v1/comments/{id}", comment.getId())).andExpect(status().isForbidden());
            http.perform(as("other", get("/api/v1/posts/{id}/comments", post.getId())))
                    .andExpect(status().isForbidden());
            http.perform(as("owner", get("/api/v1/comments/{id}", comment.getId())))
                    .andExpect(status().isOk());
        }
    }

    private boolean mayRead(Post.Status state, String actor) {
        return state == Post.Status.PUBLISHED || actor.equals("owner") || actor.equals("admin");
    }

    private MockHttpServletRequestBuilder as(String actor, MockHttpServletRequestBuilder request) {
        return actor.equals("anonymous") ? request : request.header("Authorization", "Bearer " + tokens.get(actor));
    }

    private Post savePost(Post.Status state) {
        return posts.save(Post.builder().title("post fixture").slug("post-fixture")
                .content("post content fixture").status(state).author(owner).build());
    }

    private Comment saveComment(Post post, Comment parent) {
        return comments.save(Comment.builder().post(post).author(owner).parent(parent)
                .depth(parent == null ? 0 : 1).content("comment-content-fixture").build());
    }
}
