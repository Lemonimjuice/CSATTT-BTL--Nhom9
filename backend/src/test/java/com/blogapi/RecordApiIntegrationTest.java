package com.blogapi;

import com.blogapi.entity.User;
import com.blogapi.entity.Post;
import com.blogapi.entity.RefreshToken;
import com.blogapi.repository.PostRepository;
import com.blogapi.repository.RefreshTokenRepository;
import com.blogapi.repository.RecordRepository;
import com.blogapi.repository.UserRepository;
import com.blogapi.security.JwtService;
import com.blogapi.security.UserDetailsServiceImpl;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.autoconfigure.web.servlet.MockMvcPrint;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;

import java.time.Instant;
import java.util.Map;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@SpringBootTest
@AutoConfigureMockMvc(print = MockMvcPrint.NONE)
@TestPropertySource(properties = {
        "spring.datasource.url=jdbc:h2:mem:recordapitest;MODE=PostgreSQL;DB_CLOSE_DELAY=-1",
        "spring.datasource.username=sa",
        "spring.datasource.password=",
        "spring.datasource.driver-class-name=org.h2.Driver",
        "spring.jpa.hibernate.ddl-auto=create-drop",
        "spring.jpa.show-sql=false",
        "spring.jpa.properties.hibernate.dialect=org.hibernate.dialect.H2Dialect",
        "app.jwt.secret=cmVjb3JkLWFwaS10ZXN0LXNpZ25pbmcta2V5LWF0LWxlYXN0LTMyLWJ5dGVzLWxvbmc=",
        "logging.level.org.hibernate.SQL=OFF"
})
class RecordApiIntegrationTest {

    @Autowired MockMvc mockMvc;
    @Autowired UserRepository userRepository;
    @Autowired RecordRepository recordRepository;
    @Autowired PostRepository postRepository;
    @Autowired RefreshTokenRepository refreshTokenRepository;
    @Autowired PasswordEncoder passwordEncoder;
    @Autowired UserDetailsServiceImpl userDetailsService;
    @Autowired JwtService jwtService;
    @Autowired ObjectMapper objectMapper;

    private String ownerToken;
    private String otherToken;

    @BeforeEach
    void setUp() {
        refreshTokenRepository.deleteAll();
        postRepository.deleteAll();
        recordRepository.deleteAll();
        userRepository.deleteAll();
        User owner = saveUser("record-owner", "owner@example.test");
        User other = saveUser("record-other", "other@example.test");
        ownerToken = tokenFor(owner.getUsername());
        otherToken = tokenFor(other.getUsername());
    }

    @Test
    void requiresAuthentication() throws Exception {
        mockMvc.perform(post("/api/v1/secure/records")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"secret\"}"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/v1/secure/records/1"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void createsAndReadsOnlyForOwner() throws Exception {
        String response = mockMvc.perform(post("/api/v1/secure/records")
                        .header("Authorization", "Bearer " + ownerToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"content\":\"my private record\",\"ownerId\":9999}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.content").value("my private record"))
                .andReturn().getResponse().getContentAsString();
        Integer id = com.jayway.jsonpath.JsonPath.read(response, "$.id");

        mockMvc.perform(get("/api/v1/secure/records/{id}", id)
                        .header("Authorization", "Bearer " + ownerToken))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.content").value("my private record"));

        mockMvc.perform(get("/api/v1/secure/records/{id}", id)
                        .header("Authorization", "Bearer " + otherToken))
                .andExpect(status().isForbidden());
    }

    @Test
    void returnsNotFoundForMissingRecord() throws Exception {
        mockMvc.perform(get("/api/v1/secure/records/999999")
                        .header("Authorization", "Bearer " + ownerToken))
                .andExpect(status().isNotFound());
    }

    @Test
    void searchesOnlyAuthenticatedOwnersRecordsUsingLiteralCaseInsensitiveText() throws Exception {
        saveRecord("record-owner", "Alpha private report");
        saveRecord("record-owner", "Beta private report");
        saveRecord("record-other", "Alpha belongs to someone else");

        mockMvc.perform(post("/api/v1/secure/records/search")
                        .header("Authorization", "Bearer " + ownerToken)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of(
                                "keyword", "ALPHA", "ownerId", 9999, "username", "record-other"))))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].content").value("Alpha private report"));
    }

    @ParameterizedTest
    @ValueSource(strings = {"' OR 1=1 -- ", "' UNION SELECT id, password FROM users -- ", "%", "_", "'"})
    void sqlPayloadAndWildcardsAreLiteralAndCannotBypassOwnership(String keyword) throws Exception {
        saveRecord("record-owner", "ordinary record");
        saveRecord("record-other", "other owners record");
        String body = objectMapper.writeValueAsString(Map.of("keyword", keyword));

        mockMvc.perform(post("/api/v1/secure/records/search")
                        .header("Authorization", "Bearer " + ownerToken)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(0));

        saveRecord("record-owner", "literal " + keyword + " fixture");
        saveRecord("record-other", "literal " + keyword + " private to other");
        mockMvc.perform(post("/api/v1/secure/records/search")
                        .header("Authorization", "Bearer " + ownerToken)
                        .contentType(MediaType.APPLICATION_JSON).content(body))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].content").value("literal " + keyword + " fixture"));
    }

    @Test
    void searchRequiresJwtAndRejectsInvalidInput() throws Exception {
        String endpoint = "/api/v1/secure/records/search";
        mockMvc.perform(post(endpoint).contentType(MediaType.APPLICATION_JSON).content("{\"keyword\":\"alpha\"}"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(post(endpoint).header("Authorization", "Bearer invalid-token")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"keyword\":\"alpha\"}"))
                .andExpect(status().isUnauthorized());
        for (String body : new String[]{"{}", "{\"keyword\":null}", "{\"keyword\":\" \"}",
                objectMapper.writeValueAsString(Map.of("keyword", "x".repeat(201))), "{invalid"}) {
            mockMvc.perform(post(endpoint).header("Authorization", "Bearer " + ownerToken)
                            .contentType(MediaType.APPLICATION_JSON).content(body))
                    .andExpect(status().isBadRequest());
        }
    }

    @Test
    void searchHasBoundedResults() throws Exception {
        for (int i = 0; i < 51; i++) saveRecord("record-owner", "bounded " + i);
        mockMvc.perform(post("/api/v1/secure/records/search")
                        .header("Authorization", "Bearer " + ownerToken)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"keyword\":\"bounded\"}"))
                .andExpect(status().isOk()).andExpect(jsonPath("$.length()").value(50));
    }

    @Test
    void vulnerableRouteIsAbsentByDefaultEvenWithValidJwt() throws Exception {
        mockMvc.perform(post("/api/v1/vuln/records/search")
                        .header("Authorization", "Bearer " + ownerToken)
                        .contentType(MediaType.APPLICATION_JSON).content("{\"keyword\":\"alpha\"}"))
                .andExpect(status().isNotFound());
        mockMvc.perform(post("/api/v1/vuln/records/search")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"keyword\":\"alpha\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void registrationLoginAndEnabledRefreshStillWork() throws Exception {
        mockMvc.perform(post("/api/v1/auth/register").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"username\":\"new-user\",\"email\":\"new@example.test\",\"password\":\"test-password\"}"))
                .andExpect(status().isCreated()).andExpect(jsonPath("$.accessToken").isNotEmpty());
        String login = mockMvc.perform(post("/api/v1/auth/login").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"username\":\"record-owner\",\"password\":\"test-password\"}"))
                .andExpect(status().isOk()).andReturn().getResponse().getContentAsString();
        String refreshToken = objectMapper.readTree(login).get("refreshToken").asText();
        mockMvc.perform(post("/api/v1/auth/refresh").contentType(MediaType.APPLICATION_JSON)
                        .content(objectMapper.writeValueAsString(Map.of("refreshToken", refreshToken))))
                .andExpect(status().isOk()).andExpect(jsonPath("$.accessToken").isNotEmpty());
    }

    private void saveRecord(String username, String content) {
        recordRepository.save(com.blogapi.entity.Record.builder().content(content)
                .owner(userRepository.findByUsername(username).orElseThrow()).build());
    }

    @Test
    void disabledAccountCannotUsePreviouslyIssuedJwt() throws Exception {
        User disabled = saveUser("record-disabled", "disabled@example.test");
        String token = tokenFor(disabled.getUsername());
        disabled.setEnabled(false);
        userRepository.save(disabled);

        mockMvc.perform(get("/api/v1/secure/records/1")
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void disabledAccountCannotRefreshAccessToken() throws Exception {
        User disabled = saveUser("refresh-disabled", "refresh-disabled@example.test");
        RefreshToken refreshToken = refreshTokenRepository.save(RefreshToken.builder()
                .token("refresh-test-token")
                .user(disabled)
                .expiresAt(Instant.now().plusSeconds(3600))
                .build());
        disabled.setEnabled(false);
        userRepository.save(disabled);

        mockMvc.perform(post("/api/v1/auth/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"refreshToken\":\"" + refreshToken.getToken() + "\"}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    void unpublishedPostsAreOnlyVisibleToOwnerOrAdminByIdAndSlug() throws Exception {
        Post draft = savePost("draft", Post.Status.DRAFT, userRepository.findByUsername("record-owner").orElseThrow());
        Post archived = savePost("archived", Post.Status.ARCHIVED, userRepository.findByUsername("record-owner").orElseThrow());
        User admin = saveUser("post-admin", "post-admin@example.test");
        admin.setRole(User.Role.ADMIN);
        userRepository.save(admin);
        String adminToken = tokenFor(admin.getUsername());

        for (String path : new String[]{"/api/v1/posts/" + draft.getId(), "/api/v1/posts/slug/draft"}) {
            mockMvc.perform(get(path)).andExpect(status().isForbidden());
            mockMvc.perform(get(path).header("Authorization", "Bearer " + ownerToken)).andExpect(status().isOk());
            mockMvc.perform(get(path).header("Authorization", "Bearer " + otherToken)).andExpect(status().isForbidden());
            mockMvc.perform(get(path).header("Authorization", "Bearer " + adminToken)).andExpect(status().isOk());
        }
        for (String path : new String[]{"/api/v1/posts/" + archived.getId(), "/api/v1/posts/slug/archived"}) {
            mockMvc.perform(get(path)).andExpect(status().isForbidden());
            mockMvc.perform(get(path).header("Authorization", "Bearer " + ownerToken)).andExpect(status().isOk());
        }
    }

    @Test
    void publishedPostsRemainPublicAndPostsMeRequiresAuthentication() throws Exception {
        Post published = savePost("published", Post.Status.PUBLISHED,
                userRepository.findByUsername("record-owner").orElseThrow());
        mockMvc.perform(get("/api/v1/posts/" + published.getId())).andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/posts/slug/published")).andExpect(status().isOk());
        mockMvc.perform(get("/api/v1/posts/me")).andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/v1/posts/me").header("Authorization", "Bearer " + ownerToken))
                .andExpect(status().isOk());
    }

    private Post savePost(String slug, Post.Status status, User author) {
        return postRepository.save(Post.builder()
                .title(slug)
                .slug(slug)
                .content("test content")
                .status(status)
                .author(author)
                .build());
    }

    private User saveUser(String username, String email) {
        return userRepository.save(User.builder()
                .username(username)
                .email(email)
                .password(passwordEncoder.encode("test-password"))
                .role(User.Role.USER)
                .enabled(true)
                .build());
    }

    private String tokenFor(String username) {
        return jwtService.generateAccessToken(userDetailsService.loadUserByUsername(username));
    }
}
