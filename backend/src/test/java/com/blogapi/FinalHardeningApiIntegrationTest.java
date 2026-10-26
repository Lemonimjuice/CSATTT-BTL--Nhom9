package com.blogapi;

import com.blogapi.entity.*;
import com.blogapi.repository.*;
import com.blogapi.security.JwtService;
import com.blogapi.security.UserDetailsServiceImpl;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.*;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.MockMvcPrint;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.SpyBean;
import org.springframework.data.domain.Pageable;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest
@AutoConfigureMockMvc(print = MockMvcPrint.NONE)
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:finalapi;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa", "spring.datasource.password=", "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.jpa.hibernate.ddl-auto=create-drop", "spring.jpa.show-sql=false",
        "spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.H2Dialect",
        // Deterministic signing fixture for this isolated H2 test context only.
        "app.jwt.secret=cmVjb3JkLWFwaS10ZXN0LXNpZ25pbmcta2V5LWF0LWxlYXN0LTMyLWJ5dGVzLWxvbmc=",
        "logging.level.org.hibernate.SQL=OFF"
})
class FinalHardeningApiIntegrationTest {
    @Autowired MockMvc http;
    @Autowired UserRepository users;
    @SpyBean PostRepository posts;
    @Autowired CommentRepository comments;
    @Autowired CategoryRepository categories;
    @Autowired RefreshTokenRepository refreshTokens;
    @Autowired JwtService jwt;
    @Autowired UserDetailsServiceImpl details;
    @Autowired PasswordEncoder passwords;
    @Autowired ObjectMapper json;
    private User owner, other;
    private Post published, draft;
    private Comment comment;
    private Category category;
    private String ownerToken, otherToken;

    @BeforeAll
    void actors() {
        owner = user("freeze-owner"); other = user("freeze-other");
        ownerToken = jwt.generateAccessToken(details.loadUserByUsername(owner.getUsername()));
        otherToken = jwt.generateAccessToken(details.loadUserByUsername(other.getUsername()));
    }

    @BeforeEach
    void data() {
        refreshTokens.deleteAll(); comments.deleteAll(); posts.deleteAll(); categories.deleteAll();
        category = categories.save(Category.builder().name("fixture").slug("fixture").build());
        published = postFixture("published", Post.Status.PUBLISHED, owner);
        draft = postFixture("draft", Post.Status.DRAFT, owner);
        postFixture("archived", Post.Status.ARCHIVED, owner);
        postFixture("other", Post.Status.PUBLISHED, other);
        comment = comments.save(Comment.builder().post(published).author(other).content("public fixture").build());
        comments.save(Comment.builder().post(published).author(owner).content("reply fixture").parent(comment).depth(1).build());
        clearInvocations(posts);
    }

    @ParameterizedTest
    @ValueSource(strings = {"author.password", "abc", "content", "title,sideways", "title,asc,extra", "title,"})
    void unsafeOrUnknownSortReturns400BeforeRepositoryQuery(String sort) throws Exception {
        http.perform(get("/api/v1/posts").param("sort", sort)).andExpect(status().isBadRequest());
        verify(posts, never()).findAllByStatus(any(), any());
    }

    @ParameterizedTest
    @ValueSource(strings = {"id,asc", "title,desc", "createdAt,asc", "updatedAt,desc"})
    void allowedSortStillWorks(String sort) throws Exception {
        http.perform(get("/api/v1/posts").param("sort", sort)).andExpect(status().isOk())
                .andExpect(jsonPath("$.totalElements").value(2));
    }

    @ParameterizedTest
    @ValueSource(strings = {"page", "size"})
    void invalidPaginationReturns400(String name) throws Exception {
        http.perform(get("/api/v1/posts").param(name, name.equals("page") ? "-1" : "0"))
                .andExpect(status().isBadRequest());
    }

    @ParameterizedTest
    @ValueSource(strings = {"list", "detail", "slug", "category", "author", "search", "comments", "comment"})
    void publicPostAndCommentResponsesNeverContainEmail(String endpoint) throws Exception {
        String path = switch (endpoint) {
            case "list" -> "/api/v1/posts";
            case "detail" -> "/api/v1/posts/" + published.getId();
            case "slug" -> "/api/v1/posts/slug/published";
            case "category" -> "/api/v1/posts/category/" + category.getId();
            case "author" -> "/api/v1/posts/author/" + owner.getId();
            case "search" -> "/api/v1/posts/search?q=fixture";
            case "comments" -> "/api/v1/posts/" + published.getId() + "/comments";
            default -> "/api/v1/comments/" + comment.getId();
        };
        String body = http.perform(get(path)).andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        assertThat(json.readTree(body).findValues("email")).isEmpty();
        assertThat(body).doesNotContain(owner.getEmail(), other.getEmail()).contains("username");
    }

    @Test
    void loginStillReturnsOnlyTheAuthenticatedUsersEmail() throws Exception {
        http.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"username\":\"freeze-owner\",\"password\":\"fixture-password\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.user.email").value(owner.getEmail()));
    }

    @Test
    void myPostsIncludesAllOwnStatusesWithoutTheUnusedFindAllQuery() throws Exception {
        String body = http.perform(get("/api/v1/posts/me").header("Authorization", "Bearer " + ownerToken))
                .andExpect(status().isOk()).andExpect(jsonPath("$.totalElements").value(3))
                .andReturn().getResponse().getContentAsString();
        assertThat(body).contains("DRAFT", "ARCHIVED", "PUBLISHED").doesNotContain("freeze-other");
        verify(posts, never()).findAll(any(Pageable.class));
    }

    @Test
    void privatePostReadErrorSaysRead() throws Exception {
        http.perform(get("/api/v1/posts/{id}", draft.getId()).header("Authorization", "Bearer " + otherToken))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.message").value("You do not have permission to read this post"));
    }

    @ParameterizedTest
    @ValueSource(strings = {"post-create", "post-put", "post-delete", "category-create", "category-put", "category-delete", "comment-create", "comment-put", "comment-delete", "me"})
    void anonymousProtectedRequestsAre401(String operation) throws Exception {
        http.perform(operation(operation)).andExpect(status().isUnauthorized());
        http.perform(operation(operation).header("Authorization", "Bearer invalid-fixture-jwt"))
                .andExpect(status().isUnauthorized());
    }

    @ParameterizedTest
    @ValueSource(strings = {"post-put", "post-delete", "category-create", "category-put", "category-delete"})
    void authenticatedButUnauthorizedRequestsAre403(String operation) throws Exception {
        http.perform(operation(operation).header("Authorization", "Bearer " + otherToken))
                .andExpect(status().isForbidden());
    }

    private MockHttpServletRequestBuilder operation(String op) {
        MockHttpServletRequestBuilder request = switch (op) {
            case "post-create" -> post("/api/v1/posts");
            case "post-put" -> put("/api/v1/posts/" + published.getId());
            case "post-delete" -> delete("/api/v1/posts/" + published.getId());
            case "category-create" -> post("/api/v1/categories");
            case "category-put" -> put("/api/v1/categories/" + category.getId());
            case "category-delete" -> delete("/api/v1/categories/" + category.getId());
            case "comment-create" -> post("/api/v1/posts/" + published.getId() + "/comments");
            case "comment-put" -> put("/api/v1/comments/" + comment.getId());
            case "comment-delete" -> delete("/api/v1/comments/" + comment.getId());
            default -> get("/api/v1/posts/me");
        };
        return request.contentType(MediaType.APPLICATION_JSON).content("{\"title\":\"fixture\",\"content\":\"fixture\",\"name\":\"fixture\"}");
    }

    private User user(String name) {
        return users.save(User.builder().username(name).email(name + "@example.test")
                .password(passwords.encode("fixture-password")).role(User.Role.USER).enabled(true).build());
    }
    private Post postFixture(String slug, Post.Status state, User author) {
        return posts.save(Post.builder().title("fixture " + slug).slug(slug).content("fixture content")
                .status(state).author(author).category(category).build());
    }
}
