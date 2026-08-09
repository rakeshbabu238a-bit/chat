package com.example.chat.controller;

import com.example.chat.dto.AuthResponse;
import com.example.chat.dto.LoginRequest;
import com.example.chat.dto.RegisterRequest;
import com.example.chat.model.User;
import com.example.chat.security.JwtUtil;
import com.example.chat.service.UserService;
import jakarta.validation.Valid;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.ResponseEntity;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.AuthenticationException;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@Slf4j
@RestController
@RequestMapping("/api/auth")
@RequiredArgsConstructor
public class AuthController {

    private final UserService userService;
    private final AuthenticationManager authenticationManager;
    private final JwtUtil jwtUtil;

    /**
     * POST /api/auth/login
     * Authenticate user. Only approved users can login.
     */
    @PostMapping("/login")
    public ResponseEntity<AuthResponse> login(@Valid @RequestBody LoginRequest request) {
        log.info("POST /api/auth/login - username: {}", request.getUsername());

        if (!userService.isApproved(request.getUsername())) {
            return ResponseEntity.status(403).body(new AuthResponse(
                    "Your account is not active. Contact the administrator.",
                    null,
                    request.getUsername(),
                    null
            ));
        }

        try {
            Authentication authentication = authenticationManager.authenticate(
                    new UsernamePasswordAuthenticationToken(request.getUsername(), request.getPassword())
            );

            String token = jwtUtil.generateToken(authentication.getName());
            User user = userService.findByUsername(authentication.getName());

            return ResponseEntity.ok(new AuthResponse(
                    "Login successful",
                    token,
                    authentication.getName(),
                    user.getRole().name()
            ));
        } catch (AuthenticationException e) {
            log.warn("Login failed for user: {}", request.getUsername());
            return ResponseEntity.status(401).body(new AuthResponse(
                    "Invalid username or password",
                    null,
                    null,
                    null
            ));
        }
    }

    /**
     * POST /api/auth/admin/create-user
     * Admin-only: create a new user (auto-approved).
     */
    @PostMapping("/admin/create-user")
    public ResponseEntity<Map<String, String>> createUser(
            @RequestHeader("Authorization") String authHeader,
            @Valid @RequestBody RegisterRequest request) {

        // Verify caller is admin
        String callerUsername = extractAndValidateAdmin(authHeader);
        if (callerUsername == null) {
            return ResponseEntity.status(403).body(Map.of("error", "Admin access required"));
        }

        log.info("POST /api/auth/admin/create-user - admin: {}, new user: {}", callerUsername, request.getUsername());

        try {
            User user = userService.createUser(request);
            return ResponseEntity.ok(Map.of(
                    "message", "User created successfully",
                    "username", user.getUsername(),
                    "email", user.getEmail()
            ));
        } catch (RuntimeException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * GET /api/auth/admin/users
     * Admin-only: list all users.
     */
    @GetMapping("/admin/users")
    public ResponseEntity<?> listUsers(@RequestHeader("Authorization") String authHeader) {
        String callerUsername = extractAndValidateAdmin(authHeader);
        if (callerUsername == null) {
            return ResponseEntity.status(403).body(Map.of("error", "Admin access required"));
        }

        List<Map<String, Object>> users = userService.getAllUsers().stream()
                .map(u -> Map.<String, Object>of(
                        "id", u.getId(),
                        "username", u.getUsername(),
                        "email", u.getEmail(),
                        "role", u.getRole().name(),
                        "status", u.getApprovalStatus().name(),
                        "createdAt", u.getCreatedAt().toString()
                ))
                .toList();

        return ResponseEntity.ok(users);
    }

    /**
     * DELETE /api/auth/admin/users/{id}
     * Admin-only: delete a user.
     */
    @DeleteMapping("/admin/users/{id}")
    public ResponseEntity<Map<String, String>> deleteUser(
            @RequestHeader("Authorization") String authHeader,
            @PathVariable Long id) {

        String callerUsername = extractAndValidateAdmin(authHeader);
        if (callerUsername == null) {
            return ResponseEntity.status(403).body(Map.of("error", "Admin access required"));
        }

        try {
            userService.deleteUser(id);
            return ResponseEntity.ok(Map.of("message", "User deleted"));
        } catch (RuntimeException e) {
            return ResponseEntity.badRequest().body(Map.of("error", e.getMessage()));
        }
    }

    /**
     * GET /api/auth/status
     * Check if the current JWT token is valid.
     */
    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> status(@RequestHeader("Authorization") String authHeader) {
        try {
            String token = authHeader.replace("Bearer ", "");
            String username = jwtUtil.extractUsername(token);
            if (jwtUtil.isTokenValid(token, username)) {
                User user = userService.findByUsername(username);
                return ResponseEntity.ok(Map.of(
                        "authenticated", true,
                        "username", username,
                        "role", user.getRole().name()
                ));
            }
        } catch (Exception e) {
            // Token invalid
        }
        return ResponseEntity.status(401).body(Map.of("authenticated", false));
    }

    /**
     * Extract username from token and verify the user has ADMIN role.
     * Returns username if admin, null otherwise.
     */
    private String extractAndValidateAdmin(String authHeader) {
        try {
            String token = authHeader.replace("Bearer ", "");
            String username = jwtUtil.extractUsername(token);
            if (jwtUtil.isTokenValid(token, username)) {
                User user = userService.findByUsername(username);
                if (user.getRole() == User.Role.ADMIN) {
                    return username;
                }
            }
        } catch (Exception e) {
            // Invalid token
        }
        return null;
    }
}
