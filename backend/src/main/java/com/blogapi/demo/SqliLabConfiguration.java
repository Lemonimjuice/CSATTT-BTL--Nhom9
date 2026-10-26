package com.blogapi.demo;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;

@Configuration(proxyBeanMethods = false)
@Profile("sqli-lab")
@ConditionalOnProperty(prefix = "app.demo.sqli", name = "enabled", havingValue = "true")
@EnableConfigurationProperties(SqliLabProperties.class)
public class SqliLabConfiguration {

    @Bean
    SqliLabRepository sqliLabRepository(SqliLabProperties properties,
                                      @Value("${spring.datasource.url}") String businessJdbcUrl) {
        SqliLabRepository repository = new SqliLabRepository(properties, businessJdbcUrl);
        repository.verifyAtStartup();
        return repository;
    }
}
