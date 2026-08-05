# ── Stage 1: build the fat JAR (includes React build via frontend-maven-plugin) ──
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app

# Copy Maven wrapper and pom first (layer cache for deps)
COPY backend/.mvn            .mvn
COPY backend/mvnw            mvnw
COPY backend/mvnw.cmd        mvnw.cmd
COPY backend/pom.xml         pom.xml

# Copy source
COPY backend/src             src

# Copy frontend source (frontend-maven-plugin builds it during package)
COPY frontend                ../frontend

RUN chmod +x mvnw && ./mvnw package -DskipTests

# ── Stage 2: minimal runtime image ───────────────────────────────────────────
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

COPY --from=builder /app/target/chat-backend-1.0.0.jar app.jar

EXPOSE 8082

ENTRYPOINT ["java", "-jar", "app.jar"]
