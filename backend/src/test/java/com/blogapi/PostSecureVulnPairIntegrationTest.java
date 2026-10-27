package com.blogapi;

import com.blogapi.demo.SqliLabRepository;
import com.blogapi.entity.Post;
import com.blogapi.entity.User;
import com.blogapi.repository.PostRepository;
import com.blogapi.repository.UserRepository;
import com.blogapi.security.JwtService;
import com.blogapi.security.UserDetailsServiceImpl;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.TestInstance;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.MockMvcPrint;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;

import java.util.HashMap;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * The /secure vs /vuln Post pair used by Demo 4: the patched routes enforce login and ownership,
 * the lab copies deliberately keep the original bugs (public draft read, author email, IDOR).
 * The SQLi lab repository is mocked: only the Post endpoints are exercised here.
 */
@SpringBootTest
@AutoConfigureMockMvc(print = MockMvcPrint.NONE)
@TestInstance(TestInstance.Lifecycle.PER_CLASS)
@ActiveProfiles("sqli-lab")
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:postpair;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa", "spring.datasource.password=",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.jpa.hibernate.ddl-auto=create-drop", "spring.jpa.show-sql=false",
        "spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.H2Dialect",
        "app.jwt.secret=cmVjb3JkLWFwaS10ZXN0LXNpZ25pbmcta2V5LWF0LWxlYXN0LTMyLWJ5dGVzLWxvbmc=",
        "app.demo.sqli.enabled=true",
        "app.demo.sqli.jdbc-url=jdbc:postgresql://unused-lab-host/sqli_lab",
        "app.demo.sqli.username=sqli_demo_reader",
        "app.demo.sqli.password=unused-test-fixture",
        "logging.level.org.hibernate.SQL=OFF"
})
class PostSecureVulnPairIntegrationTest {
    @Autowired MockMvc http;
    @Autowired UserRepository users;
    @Autowired PostRepository posts;
    @Autowired JwtService jwt;
    @Autowired UserDetailsServiceImpl userDetails;
    @MockBean SqliLabRepository sqliLab;
    private final Map<String, String> tokens = new HashMap<>();
    private User owner;
    private Post draft;

    @BeforeAll
    void createActors() {
        for (String actor : new String[]{"owner", "other", "admin"}) {
            User user = users.save(User.builder().username("pair-" + actor)
                    .email(actor + "@pair.example.test").password("unused-jwt-only-test-fixture")
                    .role(actor.equals("admin") ? User.Role.ADMIN : User.Role.USER)
                    .enabled(true).build());
            if (actor.equals("owner")) owner = user;
            tokens.put(actor, jwt.generateAccessToken(userDetails.loadUserByUsername(user.getUsername())));
        }
    }

    @BeforeEach
    void createDraft() {
        posts.deleteAll();
        draft = posts.save(Post.builder().title("Owner draft").slug("owner-draft-" + System.nanoTime())
                .content("draft content fixture").status(Post.Status.DRAFT).author(owner).build());
    }

    // ── Patched /api/v1/secure/posts ─────────────────────────────────────────

    @Test
    void secureReadRequiresLoginThenOwnership() throws Exception {
        http.perform(get("/api/v1/secure/posts/{id}", draft.getId())).andExpect(status().isUnauthorized());
        http.perform(as("other", get("/api/v1/secure/posts/{id}", draft.getId()))).andExpect(status().isForbidden());
        http.perform(as("admin", get("/api/v1/secure/posts/{id}", draft.getId()))).andExpect(status().isOk());
        http.perform(as("owner", get("/api/v1/secure/posts/{id}", draft.getId())))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("DRAFT"))
                .andExpect(jsonPath("$.author.username").value(owner.getUsername()))
                .andExpect(jsonPath("$.author.email").doesNotExist());
    }

    @Test
    void secureUpdateRequiresLoginThenOwnership() throws Exception {
        http.perform(json(put("/api/v1/secure/posts/{id}", draft.getId()), "{\"title\":\"anonymous edit\"}"))
                .andExpect(status().isUnauthorized());
        http.perform(as("other", json(put("/api/v1/secure/posts/{id}", draft.getId()), "{\"title\":\"other edit\"}")))
                .andExpect(status().isForbidden());
        assertThat(posts.findById(draft.getId()).orElseThrow().getTitle()).isEqualTo("Owner draft");
        http.perform(as("owner", json(put("/api/v1/secure/posts/{id}", draft.getId()), "{\"title\":\"owner edit\"}")))
                .andExpect(status().isOk());
        assertThat(posts.findById(draft.getId()).orElseThrow().getTitle()).isEqualTo("owner edit");
    }

    @Test
    void secureDeleteRequiresLoginThenOwnership() throws Exception {
        http.perform(delete("/api/v1/secure/posts/{id}", draft.getId())).andExpect(status().isUnauthorized());
        http.perform(as("other", delete("/api/v1/secure/posts/{id}", draft.getId()))).andExpect(status().isForbidden());
        assertThat(posts.existsById(draft.getId())).isTrue();
        http.perform(as("owner", delete("/api/v1/secure/posts/{id}", draft.getId()))).andExpect(status().isNoContent());
        assertThat(posts.existsById(draft.getId())).isFalse();
    }

    @Test
    void publicPostRouteAnswersAnonymousDraftReadWith401() throws Exception {
        http.perform(get("/api/v1/posts/{id}", draft.getId())).andExpect(status().isUnauthorized());
        http.perform(as("other", get("/api/v1/posts/{id}", draft.getId()))).andExpect(status().isForbidden());
    }

    // ── Deliberately vulnerable /api/v1/vuln/posts ───────────────────────────

    @Test
    void vulnReadExposesDraftAndEmailToAnonymousCallers() throws Exception {
        http.perform(get("/api/v1/vuln/posts/{id}", draft.getId()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("DRAFT"))
                .andExpect(jsonPath("$.author.email").value(owner.getEmail()));
    }

    @Test
    void vulnUpdateSkipsOwnershipCheck() throws Exception {
        http.perform(json(put("/api/v1/vuln/posts/{id}", draft.getId()), "{\"title\":\"anonymous edit\"}"))
                .andExpect(status().isUnauthorized());
        http.perform(as("other", json(put("/api/v1/vuln/posts/{id}", draft.getId()), "{\"title\":\"edited by other\"}")))
                .andExpect(status().isOk());
        assertThat(posts.findById(draft.getId()).orElseThrow().getTitle()).isEqualTo("edited by other");
    }

    @Test
    void vulnDeleteSkipsOwnershipCheck() throws Exception {
        http.perform(as("other", delete("/api/v1/vuln/posts/{id}", draft.getId()))).andExpect(status().isNoContent());
        assertThat(posts.existsById(draft.getId())).isFalse();
    }

    private MockHttpServletRequestBuilder as(String actor, MockHttpServletRequestBuilder request) {
        return request.header("Authorization", "Bearer " + tokens.get(actor));
    }

    private static MockHttpServletRequestBuilder json(MockHttpServletRequestBuilder request, String body) {
        return request.contentType(MediaType.APPLICATION_JSON).content(body);
    }
}
