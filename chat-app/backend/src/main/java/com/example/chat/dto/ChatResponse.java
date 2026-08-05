package com.example.chat.dto;

import lombok.AllArgsConstructor;
import lombok.Getter;
import lombok.NoArgsConstructor;
import lombok.Setter;

@Getter
@Setter
@NoArgsConstructor
@AllArgsConstructor
public class ChatResponse {

    private String reply;       // The assistant's reply text
    private String model;       // e.g. "gpt-4o-mini"
    private int promptTokens;
    private int completionTokens;
    private int totalTokens;
}
