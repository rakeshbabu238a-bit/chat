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

@Slf4j
@Service
@RequiredArgsConstructor
public class UserService {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;
    private final EmailService emailService;

    /**
     * Register a new user. The account starts in PENDING status.
     * An approval email is sent to the admin.
     */
    @Transactional
    public User register(RegisterRequest request) {
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
                .build();

        User savedUser = userRepository.save(user);
        log.info("New user registered: {} (pending approval)", savedUser.getUsername());

        // Send approval request email to admin
        emailService.sendApprovalRequestEmail(savedUser);

        return savedUser;
    }

    /**
     * Approve a user by their approval token.
     */
    @Transactional
    public User approveUser(String token) {
        User user = userRepository.findByApprovalToken(token)
                .orElseThrow(() -> new RuntimeException("Invalid approval token"));

        if (user.getApprovalStatus() == User.ApprovalStatus.APPROVED) {
            throw new RuntimeException("User is already approved");
        }

        user.setApprovalStatus(User.ApprovalStatus.APPROVED);
        user.setApprovedAt(LocalDateTime.now());
        User approvedUser = userRepository.save(user);

        log.info("User approved: {}", approvedUser.getUsername());

        // Notify the user that their account is now active
        emailService.sendAccountApprovedEmail(approvedUser);

        return approvedUser;
    }

    /**
     * Reject a user by their approval token.
     */
    @Transactional
    public User rejectUser(String token) {
        User user = userRepository.findByApprovalToken(token)
                .orElseThrow(() -> new RuntimeException("Invalid approval token"));

        if (user.getApprovalStatus() == User.ApprovalStatus.REJECTED) {
            throw new RuntimeException("User is already rejected");
        }

        user.setApprovalStatus(User.ApprovalStatus.REJECTED);
        User rejectedUser = userRepository.save(user);

        log.info("User rejected: {}", rejectedUser.getUsername());

        // Notify the user about the rejection
        emailService.sendAccountRejectedEmail(rejectedUser);

        return rejectedUser;
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
