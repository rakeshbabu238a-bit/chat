import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';

const _groqApiUrl =
    'https://api.groq.com/openai/v1/chat/completions';
const _defaultModel = 'llama-3.3-70b-versatile';
const _systemPrompt =
    'You are a helpful, concise, and friendly AI assistant. Answer questions clearly and accurately.';

/// Response from Groq — mirrors the original Spring Boot ChatResponse DTO.
class GroqResponse {
  final String reply;
  final String model;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  const GroqResponse({
    required this.reply,
    required this.model,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });
}

/// Calls the Groq API directly from the Flutter app.
///
/// NOTE: For production, move the API key to a Firebase Cloud Function
/// so it is never shipped in the client bundle. See functions/index.js.
class GroqService {
  final String apiKey;
  final String model;
  final http.Client _client;

  GroqService({
    required this.apiKey,
    this.model = _defaultModel,
    http.Client? client,
  }) : _client = client ?? http.Client();

  /// Sends the full conversation history to Groq and returns the reply.
  Future<GroqResponse> chat(List<ChatMessage> history) async {
    // Build the messages array: system prompt + conversation history
    final messages = <Map<String, String>>[
      {'role': 'system', 'content': _systemPrompt},
      // Exclude error-role messages from the API payload
      ...history
          .where((m) => m.role != MessageRole.error)
          .map((m) => m.toApiMessage()),
    ];

    final body = jsonEncode({
      'model': model,
      'messages': messages,
      'temperature': 0.7,
      'max_tokens': 1024,
    });

    debugPrint('[GroqService] Sending ${messages.length} message(s) to Groq');

    final response = await _client.post(
      Uri.parse(_groqApiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      final err = jsonDecode(response.body);
      final msg = err['error']?['message'] ?? 'Groq request failed (${response.statusCode})';
      throw Exception(msg);
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final reply = json['choices'][0]['message']['content'] as String;
    final usage = json['usage'] as Map<String, dynamic>;
    final usedModel = json['model'] as String? ?? model;

    debugPrint('[GroqService] Reply received [tokens=${usage['total_tokens']}]');

    return GroqResponse(
      reply: reply,
      model: usedModel,
      promptTokens: usage['prompt_tokens'] as int? ?? 0,
      completionTokens: usage['completion_tokens'] as int? ?? 0,
      totalTokens: usage['total_tokens'] as int? ?? 0,
    );
  }

  void dispose() => _client.close();
}
