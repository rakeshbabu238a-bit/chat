package com.example.chat.service;

import com.example.chat.dto.RegisterRequest;
import com.example.chat.model.User;
import com.example.chat.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.time.LocalDateTime;
import java.util.List;

@Slf4j
@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    /**
     * Admin creates a new user. The account is auto-approved and ready to login.
     */
    @Transactional
    public User createUser(RegisterRequest request) {
        if (userRepository.existsByUsername(request.getUsername())) {
            throw new RuntimeException("Username already exists");
        }
        if (userRepository.existsByEmail(request.getEmail())) {
            throw new RuntimeException("Email already exists");
        }

        User user = User.builder()
                .username(request.getUsername())
                .email(request.getEmail())
                .password(passwordEncoder.encode(request.getPassword()))
                .approvalStatus(User.ApprovalStatus.APPROVED)
                .approvedAt(LocalDateTime.now())
                .role(User.Role.USER)
                .build();

        User savedUser = userRepository.save(user);
        log.info("Admin created user: {} (auto-approved)", savedUser.getUsername());

        return savedUser;
    }

    /**
     * Get all users (for admin panel).
     */
    public List<User> getAllUsers() {
        return userRepository.findAll();
    }

    /**
     * Delete a user by ID (admin only).
     */
    @Transactional
    public void deleteUser(Long userId) {
        User user = userRepository.findById(userId)
                .orElseThrow(() -> new RuntimeException("User not found"));
        if (user.getRole() == User.Role.ADMIN) {
            throw new RuntimeException("Cannot delete admin user");
        }
        userRepository.delete(user);
        log.info("Admin deleted user: {}", user.getUsername());
    }

    /**
     * Find a user by username (used during authentication).
     */
    public User findByUsername(String username) {
        return userRepository.findByUsername(username)
                .orElseThrow(() -> new RuntimeException("User not found"));
    }

    /**
     * Check if a user is approved for login.
     */
    public boolean isApproved(String username) {
        User user = findByUsername(username);
        return user.getApprovalStatus() == User.ApprovalStatus.APPROVED;
    }
}
