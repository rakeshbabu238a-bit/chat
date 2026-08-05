package com.example.chat.model;

import com.fasterxml.jackson.annotation.JsonCreator;
import com.fasterxml.jackson.annotation.JsonProperty;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@NoArgsConstructor
public class ChatMessage {

    private String role;    // "user", "assistant", or "system"
    private String content;

    @JsonCreator
    public ChatMessage(@JsonProperty("role") String role,
                       @JsonProperty("content") String content) {
        this.role = role;
        this.content = content;
    }
}
