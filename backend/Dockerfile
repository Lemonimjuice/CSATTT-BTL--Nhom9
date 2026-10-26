# ─── Stage 1: Build ───────────────────────────────────────────────────────────
FROM maven:3.9.6-eclipse-temurin-21 AS builder

WORKDIR /build

# Cache dependencies first (only re-run if pom.xml changes)
COPY pom.xml .
RUN mvn dependency:go-offline -q

# Copy source and build
COPY src ./src
RUN mvn clean package -DskipTests -q

# ─── Stage 2: Runtime ─────────────────────────────────────────────────────────
FROM eclipse-temurin:21-jre-jammy AS runtime

# Create non-root user for security
RUN groupadd --system blogapi && useradd --system --gid blogapi blogapi

WORKDIR /app

# Create logs directory with correct ownership
RUN mkdir -p logs && chown -R blogapi:blogapi /app

# Copy built jar from builder stage
COPY --from=builder --chown=blogapi:blogapi /build/target/*.jar app.jar

USER blogapi

EXPOSE 8080

# JVM tuning for containers: respects cgroup memory limits
ENTRYPOINT ["java", \
  "-XX:+UseContainerSupport", \
  "-XX:MaxRAMPercentage=75.0", \
  "-XX:+UseG1GC", \
  "-Djava.security.egd=file:/dev/./urandom", \
  "-jar", "app.jar"]
