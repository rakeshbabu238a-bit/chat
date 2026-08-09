package com.example.chat.config;

import com.example.chat.model.User;
import com.example.chat.repository.UserRepository;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.CommandLineRunner;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.stereotype.Component;

import java.time.LocalDateTime;

@Slf4j
@Component
@RequiredArgsConstructor
public class AdminSeeder implements CommandLineRunner {

    private final UserRepository userRepository;
    private final PasswordEncoder passwordEncoder;

    @Value("${app.admin-email}")
    private String adminEmail;

    @Value("${app.admin-username:admin}")
    private String adminUsername;

    @Value("${app.admin-password:admin123}")
    private String adminPassword;

    @Override
    public void run(String... args) {
        if (!userRepository.existsByUsername(adminUsername)) {
            User admin = User.builder()
                    .username(adminUsername)
                    .email(adminEmail)
                    .password(passwordEncoder.encode(adminPassword))
                    .role(User.Role.ADMIN)
                    .approvalStatus(User.ApprovalStatus.APPROVED)
                    .approvedAt(LocalDateTime.now())
                    .build();

            userRepository.save(admin);
            log.info("Default admin user created: {}", adminUsername);
        }
    }
}
