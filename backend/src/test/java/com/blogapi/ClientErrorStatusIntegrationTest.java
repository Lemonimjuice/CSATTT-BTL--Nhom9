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
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.MockMvcPrint;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Malformed client requests must be answered as client errors (400/405/415), not as a server failure (500).
 * Before the fix every case below fell through GlobalExceptionHandler.handleGeneric and returned 500.
 */
@SpringBootTest
@AutoConfigureMockMvc(print = MockMvcPrint.NONE)
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:clienterrors;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa", "spring.datasource.password=",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.jpa.hibernate.ddl-auto=create-drop", "spring.jpa.show-sql=false",
        "spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.H2Dialect",
        "app.jwt.secret=cmVjb3JkLWFwaS10ZXN0LXNpZ25pbmcta2V5LWF0LWxlYXN0LTMyLWJ5dGVzLWxvbmc=",
        "logging.level.org.hibernate.SQL=OFF"
})
class ClientErrorStatusIntegrationTest {

    @Autowired MockMvc http;
    @Autowired UserRepository users;
    @Autowired PostRepository posts;
    @Autowired CommentRepository comments;
    @Autowired JwtService jwt;
    @Autowired UserDetailsServiceImpl userDetails;

    private String token;
    private Post firstPost, secondPost;
    private Comment commentOnFirst;

    @BeforeAll
    void fixtures() {
        User author = users.save(User.builder().username("client-error-user").email("client-error@example.test")
                .password("unused-jwt-only-test-fixture").role(User.Role.USER).enabled(true).build());
        token = jwt.generateAccessToken(userDetails.loadUserByUsername(author.getUsername()));
        firstPost = posts.save(Post.builder().title("first").slug("client-error-first").content("fixture")
                .status(Post.Status.PUBLISHED).author(author).build());
        secondPost = posts.save(Post.builder().title("second").slug("client-error-second").content("fixture")
                .status(Post.Status.PUBLISHED).author(author).build());
        commentOnFirst = comments.save(Comment.builder().post(firstPost).author(author)
                .content("fixture comment").build());
    }

    @Test
    void nonNumericPathIdIs400() throws Exception {
        http.perform(get("/api/v1/posts/abc")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Invalid value for parameter 'id'"));
        http.perform(auth(get("/api/v1/secure/posts/abc"))).andExpect(status().isBadRequest());
        http.perform(auth(get("/api/v1/secure/records/abc"))).andExpect(status().isBadRequest());
    }

    @Test
    void missingRequiredQueryParameterIs400() throws Exception {
        http.perform(get("/api/v1/posts/search")).andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Missing required parameter 'q'"));
    }

    @Test
    void invalidCommentPaginationIs400() throws Exception {
        http.perform(get("/api/v1/posts/{id}/comments", firstPost.getId()).param("page", "-1"))
                .andExpect(status().isBadRequest());
        http.perform(get("/api/v1/posts/{id}/comments", firstPost.getId()).param("size", "0"))
                .andExpect(status().isBadRequest());
        http.perform(get("/api/v1/posts/{id}/comments", firstPost.getId())).andExpect(status().isOk());
    }

    @Test
    void replyToCommentOfAnotherPostIs400AndNothingIsSaved() throws Exception {
        long before = comments.count();
        http.perform(auth(post("/api/v1/posts/{id}/comments", secondPost.getId()))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"reply\",\"parentId\":" + commentOnFirst.getId() + "}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.message").value("Parent comment does not belong to this post"));
        assertThat(comments.count()).isEqualTo(before);
    }

    @Test
    void unsupportedMethodIs405() throws Exception {
        http.perform(auth(post("/api/v1/posts/{id}", firstPost.getId()))).andExpect(status().isMethodNotAllowed());
    }

    @Test
    void unsupportedContentTypeIs415() throws Exception {
        http.perform(auth(post("/api/v1/secure/records/search")).contentType(MediaType.TEXT_PLAIN).content("alpha"))
                .andExpect(status().isUnsupportedMediaType());
    }

    private MockHttpServletRequestBuilder auth(MockHttpServletRequestBuilder request) {
        return request.header("Authorization", "Bearer " + token);
    }
}
