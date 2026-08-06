# -- Stage 1: build fat JAR (backend + embedded React frontend) ----------------
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app

# Copy Maven wrapper and POM first for layer caching
COPY chat-app/backend/.mvn        .mvn
COPY chat-app/backend/mvnw        mvnw
COPY chat-app/backend/pom.xml     pom.xml

# Pre-download dependencies (backend only for cache layer)
RUN chmod +x mvnw && ./mvnw dependency:go-offline -B -P backend-only

# Copy frontend source so the full build can include it
COPY chat-app/frontend             ../frontend

# Copy Java source
COPY chat-app/backend/src          src

# Full build: installs Node locally, builds React app, embeds it in the JAR
RUN ./mvnw package -DskipTests

# -- Stage 2: minimal runtime --------------------------------------------------
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

COPY --from=builder /app/target/chat-backend-1.0.0.jar app.jar

EXPOSE 8082

ENTRYPOINT ["java", "-jar", "app.jar"]
