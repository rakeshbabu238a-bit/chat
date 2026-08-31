import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';

const _defaultApiUrl =
    'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions';
const _defaultModel = 'models/gemini-3.6-flash';
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
  final String apiUrl;
  final http.Client _client;

  GroqService({
    required this.apiKey,
    this.model = _defaultModel,
    this.apiUrl = _defaultApiUrl,
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

    debugPrint('[GroqService] Sending ${messages.length} message(s)');

    final response = await _client.post(
      Uri.parse(apiUrl),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception(_extractError(response.body, response.statusCode));
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;

    final choices = json['choices'] as List<dynamic>?;
    if (choices == null || choices.isEmpty) {
      throw Exception('No response returned by the model.');
    }
    final message = (choices.first as Map<String, dynamic>)['message']
        as Map<String, dynamic>?;
    final reply = (message?['content'] as String?)?.trim() ?? '';

    final usage = (json['usage'] as Map<String, dynamic>?) ?? const {};
    final usedModel = json['model'] as String? ?? model;

    debugPrint(
        '[GroqService] Reply received [tokens=${_asInt(usage['total_tokens'])}]');

    return GroqResponse(
      reply: reply,
      model: usedModel,
      promptTokens: _asInt(usage['prompt_tokens']),
      completionTokens: _asInt(usage['completion_tokens']),
      totalTokens: _asInt(usage['total_tokens']),
    );
  }

  /// Safely pull a human-readable message out of an error response body,
  /// regardless of whether the provider returns `error` as an object,
  /// a string, or something else.
  static String _extractError(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String && message.isNotEmpty) return message;
        }
        if (error is String && error.isNotEmpty) return error;
        final message = decoded['message'];
        if (message is String && message.isNotEmpty) return message;
      }
    } catch (_) {
      // body was not valid JSON — fall through to the generic message
    }
    return 'Request failed ($statusCode)';
  }

  /// Coerce a JSON value of unknown type (int, double, String, null) to int.
  /// Different providers report token counts in different types.
  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  void dispose() => _client.close();
}
