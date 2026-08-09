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
     * POST /api/auth/register
     * Register a new user. Account will be in PENDING status until admin approves.
     */
    @PostMapping("/register")
    public ResponseEntity<AuthResponse> register(@Valid @RequestBody RegisterRequest request) {
        log.info("POST /api/auth/register - username: {}", request.getUsername());
        User user = userService.register(request);
        return ResponseEntity.ok(new AuthResponse(
                "Registration successful. Please wait for admin approval before logging in.",
                null,
                user.getUsername()
        ));
    }

    /**
     * POST /api/auth/login
     * Authenticate user. Only approved users can login.
     */
    @PostMapping("/login")
    public ResponseEntity<AuthResponse> login(@Valid @RequestBody LoginRequest request) {
        log.info("POST /api/auth/login - username: {}", request.getUsername());

        // Check if user is approved before authenticating
        if (!userService.isApproved(request.getUsername())) {
            return ResponseEntity.status(403).body(new AuthResponse(
                    "Your account is pending admin approval. Please wait for approval.",
                    null,
                    request.getUsername()
            ));
        }

        try {
            Authentication authentication = authenticationManager.authenticate(
                    new UsernamePasswordAuthenticationToken(request.getUsername(), request.getPassword())
            );

            String token = jwtUtil.generateToken(authentication.getName());
            return ResponseEntity.ok(new AuthResponse(
                    "Login successful",
                    token,
                    authentication.getName()
            ));
        } catch (AuthenticationException e) {
            log.warn("Login failed for user: {}", request.getUsername());
            return ResponseEntity.status(401).body(new AuthResponse(
                    "Invalid username or password",
                    null,
                    null
            ));
        }
    }

    /**
     * GET /api/auth/approve?token=...
     * Admin clicks this link from the email to approve a user.
     */
    @GetMapping("/approve")
    public ResponseEntity<String> approveUser(@RequestParam String token) {
        log.info("GET /api/auth/approve - token: {}", token);
        try {
            User user = userService.approveUser(token);
            String html = """
                    <html>
                    <body style="font-family: Arial, sans-serif; padding: 40px; text-align: center;">
                        <h2 style="color: #4CAF50;">✅ User Approved</h2>
                        <p>User <strong>%s</strong> (%s) has been approved and can now log in.</p>
                    </body>
                    </html>
                    """.formatted(user.getUsername(), user.getEmail());
            return ResponseEntity.ok().header("Content-Type", "text/html").body(html);
        } catch (RuntimeException e) {
            String html = """
                    <html>
                    <body style="font-family: Arial, sans-serif; padding: 40px; text-align: center;">
                        <h2 style="color: #f44336;">❌ Error</h2>
                        <p>%s</p>
                    </body>
                    </html>
                    """.formatted(e.getMessage());
            return ResponseEntity.badRequest().header("Content-Type", "text/html").body(html);
        }
    }

    /**
     * GET /api/auth/reject?token=...
     * Admin clicks this link from the email to reject a user.
     */
    @GetMapping("/reject")
    public ResponseEntity<String> rejectUser(@RequestParam String token) {
        log.info("GET /api/auth/reject - token: {}", token);
        try {
            User user = userService.rejectUser(token);
            String html = """
                    <html>
                    <body style="font-family: Arial, sans-serif; padding: 40px; text-align: center;">
                        <h2 style="color: #FF9800;">🚫 User Rejected</h2>
                        <p>User <strong>%s</strong> (%s) has been rejected.</p>
                    </body>
                    </html>
                    """.formatted(user.getUsername(), user.getEmail());
            return ResponseEntity.ok().header("Content-Type", "text/html").body(html);
        } catch (RuntimeException e) {
            String html = """
                    <html>
                    <body style="font-family: Arial, sans-serif; padding: 40px; text-align: center;">
                        <h2 style="color: #f44336;">❌ Error</h2>
                        <p>%s</p>
                    </body>
                    </html>
                    """.formatted(e.getMessage());
            return ResponseEntity.badRequest().header("Content-Type", "text/html").body(html);
        }
    }

    /**
     * GET /api/auth/status
     * Check if the current JWT token is valid (used by frontend to verify auth state).
     */
    @GetMapping("/status")
    public ResponseEntity<Map<String, Object>> status(@RequestHeader("Authorization") String authHeader) {
        try {
            String token = authHeader.replace("Bearer ", "");
            String username = jwtUtil.extractUsername(token);
            if (jwtUtil.isTokenValid(token, username)) {
                return ResponseEntity.ok(Map.of("authenticated", true, "username", username));
            }
        } catch (Exception e) {
            // Token invalid
        }
        return ResponseEntity.status(401).body(Map.of("authenticated", false));
    }
}
