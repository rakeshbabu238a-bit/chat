# -- Stage 1: build fat JAR (backend only, frontend is on GitHub Pages) --------
FROM eclipse-temurin:21-jdk-alpine AS builder
WORKDIR /app

# Copy Maven wrapper and POM first for layer caching
COPY chat-app/backend/.mvn        .mvn
COPY chat-app/backend/mvnw        mvnw
COPY chat-app/backend/pom.xml     pom.xml

# Pre-download dependencies
RUN chmod +x mvnw && ./mvnw dependency:go-offline -B -P backend-only

# Copy Java source
COPY chat-app/backend/src         src

# Build backend JAR, skip frontend build and tests
RUN ./mvnw package -DskipTests -P backend-only

# -- Stage 2: minimal runtime --------------------------------------------------
FROM eclipse-temurin:21-jre-alpine
WORKDIR /app

COPY --from=builder /app/target/chat-backend-1.0.0.jar app.jar

EXPOSE 8082

ENTRYPOINT ["java", "-jar", "app.jar"]

