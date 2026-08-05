package com.example.chat.dto;

import com.example.chat.model.ChatMessage;
import jakarta.validation.constraints.NotEmpty;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

import java.util.List;

@Getter
@Setter
@NoArgsConstructor
public class ChatRequest {

    /**
     * Full conversation history sent from the frontend.
     * Each entry has a "role" ("user" or "assistant") and "content".
     */
    @NotEmpty(message = "Messages must not be empty")
    private List<ChatMessage> messages;
}
