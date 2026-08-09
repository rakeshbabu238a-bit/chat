package com.example.chat.service;

import com.example.chat.model.User;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.mail.javamail.MimeMessageHelper;
import org.springframework.stereotype.Service;

import jakarta.mail.MessagingException;
import jakarta.mail.internet.MimeMessage;

@Slf4j
@Service
@RequiredArgsConstructor
public class EmailService {

    private final JavaMailSender mailSender;

    @Value("${app.admin-email}")
    private String adminEmail;

    @Value("${app.base-url}")
    private String baseUrl;

    @Value("${spring.mail.username:noreply@app.com}")
    private String fromEmail;

    /**
     * Send approval notification email to the admin when a new user registers.
     */
    public void sendApprovalRequestEmail(User user) {
        String approveUrl = baseUrl + "/api/auth/approve?token=" + user.getApprovalToken();
        String rejectUrl = baseUrl + "/api/auth/reject?token=" + user.getApprovalToken();

        String subject = "New User Registration - Approval Required";
        String htmlContent = """
                <html>
                <body style="font-family: Arial, sans-serif; padding: 20px;">
                    <h2 style="color: #333;">New User Registration Request</h2>
                    <p>A new user has registered and is awaiting your approval:</p>
                    <table style="border-collapse: collapse; margin: 20px 0;">
                        <tr>
                            <td style="padding: 8px; font-weight: bold;">Username:</td>
                            <td style="padding: 8px;">%s</td>
                        </tr>
                        <tr>
                            <td style="padding: 8px; font-weight: bold;">Email:</td>
                            <td style="padding: 8px;">%s</td>
                        </tr>
                        <tr>
                            <td style="padding: 8px; font-weight: bold;">Registered At:</td>
                            <td style="padding: 8px;">%s</td>
                        </tr>
                    </table>
                    <p>Please click one of the buttons below:</p>
                    <div style="margin: 20px 0;">
                        <a href="%s" style="background-color: #4CAF50; color: white; padding: 12px 24px; text-decoration: none; border-radius: 4px; margin-right: 10px;">
                            ✅ Approve
                        </a>
                        <a href="%s" style="background-color: #f44336; color: white; padding: 12px 24px; text-decoration: none; border-radius: 4px;">
                            ❌ Reject
                        </a>
                    </div>
                    <p style="color: #666; font-size: 12px;">This is an automated email from AI Chat application.</p>
                </body>
                </html>
                """.formatted(user.getUsername(), user.getEmail(), user.getCreatedAt(), approveUrl, rejectUrl);

        try {
            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");
            helper.setFrom(fromEmail);
            helper.setTo(adminEmail);
            helper.setSubject(subject);
            helper.setText(htmlContent, true);
            mailSender.send(message);
            log.info("Approval email sent to admin for user: {}", user.getUsername());
        } catch (MessagingException e) {
            log.error("Failed to send approval email for user: {}", user.getUsername(), e);
            throw new RuntimeException("Failed to send approval notification email", e);
        }
    }

    /**
     * Notify the user that their account has been approved.
     */
    public void sendAccountApprovedEmail(User user) {
        String loginUrl = baseUrl;
        String subject = "Account Approved - You Can Now Login";
        String htmlContent = """
                <html>
                <body style="font-family: Arial, sans-serif; padding: 20px;">
                    <h2 style="color: #4CAF50;">Account Approved! 🎉</h2>
                    <p>Hi %s,</p>
                    <p>Your account has been approved by the administrator. You can now log in to the AI Chat application.</p>
                    <div style="margin: 20px 0;">
                        <a href="%s" style="background-color: #2196F3; color: white; padding: 12px 24px; text-decoration: none; border-radius: 4px;">
                            Login Now
                        </a>
                    </div>
                    <p style="color: #666; font-size: 12px;">This is an automated email from AI Chat application.</p>
                </body>
                </html>
                """.formatted(user.getUsername(), loginUrl);

        try {
            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");
            helper.setFrom(fromEmail);
            helper.setTo(user.getEmail());
            helper.setSubject(subject);
            helper.setText(htmlContent, true);
            mailSender.send(message);
            log.info("Account approved email sent to user: {}", user.getUsername());
        } catch (MessagingException e) {
            log.error("Failed to send approved email to user: {}", user.getUsername(), e);
            // Don't throw here — approval already succeeded, email is best-effort
        }
    }

    /**
     * Notify the user that their account has been rejected.
     */
    public void sendAccountRejectedEmail(User user) {
        String subject = "Account Registration - Not Approved";
        String htmlContent = """
                <html>
                <body style="font-family: Arial, sans-serif; padding: 20px;">
                    <h2 style="color: #f44336;">Registration Not Approved</h2>
                    <p>Hi %s,</p>
                    <p>Unfortunately, your account registration has not been approved by the administrator.</p>
                    <p>If you believe this is a mistake, please contact the administrator.</p>
                    <p style="color: #666; font-size: 12px;">This is an automated email from AI Chat application.</p>
                </body>
                </html>
                """.formatted(user.getUsername());

        try {
            MimeMessage message = mailSender.createMimeMessage();
            MimeMessageHelper helper = new MimeMessageHelper(message, true, "UTF-8");
            helper.setFrom(fromEmail);
            helper.setTo(user.getEmail());
            helper.setSubject(subject);
            helper.setText(htmlContent, true);
            mailSender.send(message);
            log.info("Account rejected email sent to user: {}", user.getUsername());
        } catch (MessagingException e) {
            log.error("Failed to send rejected email to user: {}", user.getUsername(), e);
        }
    }
}
