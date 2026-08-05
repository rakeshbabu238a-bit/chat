package com.example.chat.service;

import com.example.chat.dto.ChatRequest;
import com.example.chat.dto.ChatResponse;
import com.example.chat.model.ChatMessage;
import com.fasterxml.jackson.databind.JsonNode;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Service;
import org.springframework.web.reactive.function.client.WebClient;
import org.springframework.web.reactive.function.client.WebClientResponseException;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

@Slf4j
@Service
public class ChatService {

    // Groq is OpenAI-API-compatible — only the base URL differs
    private static final String GROQ_API_URL = "https://api.groq.com/openai/v1/chat/completions";
    private static final String SYSTEM_PROMPT =
            "You are a helpful, concise, and friendly AI assistant. Answer questions clearly and accurately.";

    private final WebClient webClient;
    private final String model;
    private final String apiKey;

    public ChatService(WebClient.Builder webClientBuilder,
                       @Value("${groq.api.key:}") String apiKey,
                       @Value("${groq.model:llama-3.3-70b-versatile}") String model) {
        this.apiKey = apiKey;
        this.model = model;
        this.webClient = webClientBuilder
                .baseUrl(GROQ_API_URL)
                .defaultHeader(HttpHeaders.CONTENT_TYPE, MediaType.APPLICATION_JSON_VALUE)
                .build();
    }

    public ChatResponse chat(ChatRequest request) {
        if (apiKey == null || apiKey.isBlank()) {
            throw new RuntimeException(
                "GROQ_API_KEY is not configured. Set the environment variable and restart the backend.");
        }

        List<Map<String, String>> messages = new ArrayList<>();
        messages.add(Map.of("role", "system", "content", SYSTEM_PROMPT));

        for (ChatMessage msg : request.getMessages()) {
            messages.add(Map.of("role", msg.getRole(), "content", msg.getContent()));
        }

        Map<String, Object> body = new HashMap<>();
        body.put("model", model);
        body.put("messages", messages);
        body.put("temperature", 0.7);
        body.put("max_tokens", 1024);

        log.info("Calling Groq [model={}] with {} message(s)", model, messages.size());

        try {
            JsonNode response = webClient.post()
                    .header(HttpHeaders.AUTHORIZATION, "Bearer " + apiKey)
                    .bodyValue(body)
                    .retrieve()
                    .bodyToMono(JsonNode.class)
                    .block();

            String reply = response
                    .path("choices").get(0)
                    .path("message").path("content")
                    .asText();

            JsonNode usage = response.path("usage");
            int promptTokens     = usage.path("prompt_tokens").asInt();
            int completionTokens = usage.path("completion_tokens").asInt();
            int totalTokens      = usage.path("total_tokens").asInt();
            String usedModel     = response.path("model").asText(model);

            log.info("Groq response received [tokens={}]", totalTokens);
            return new ChatResponse(reply, usedModel, promptTokens, completionTokens, totalTokens);

        } catch (WebClientResponseException ex) {
            log.error("Groq API error [status={} body={}]", ex.getStatusCode(), ex.getResponseBodyAsString());
            throw new RuntimeException("LLM request failed: " + ex.getMessage(), ex);
        }
    }
}
