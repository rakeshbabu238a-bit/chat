import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

import '../models/chat_message.dart';

/// Reply from the server-side LLM proxy (Cloudflare Worker `POST /chat`).
class ChatApiResponse {
  final String reply;
  final String model;
  final int promptTokens;
  final int completionTokens;
  final int totalTokens;

  const ChatApiResponse({
    required this.reply,
    required this.model,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTokens,
  });
}

/// Calls the server-side `/chat` proxy that holds the LLM API key.
///
/// The key never reaches the client — the Flutter app only knows the proxy
/// URL, injected at build time:
///   flutter build web --dart-define=CHAT_API_URL=https://<worker>.workers.dev/chat
class ChatApiService {
  /// Proxy endpoint. Injected via --dart-define=CHAT_API_URL=...
  static const chatApiUrl = String.fromEnvironment('CHAT_API_URL');

  static bool get isConfigured => chatApiUrl.isNotEmpty;

  final String apiUrl;
  final http.Client _client;

  ChatApiService({String? apiUrl, http.Client? client})
      : apiUrl = apiUrl ?? chatApiUrl,
        _client = client ?? http.Client();

  /// Sends the conversation history to the proxy and returns the reply.
  Future<ChatApiResponse> chat(List<ChatMessage> history) async {
    if (apiUrl.trim().isEmpty) {
      throw Exception(
        'Chat backend not configured. Build with '
        '--dart-define=CHAT_API_URL=https://<your-worker>.workers.dev/chat',
      );
    }

    // Exclude error bubbles from the payload; map to {role, content}.
    final messages = history
        .where((m) => m.role != MessageRole.error)
        .map((m) => m.toApiMessage())
        .toList();

    debugPrint('[ChatApiService] POST ${messages.length} message(s) -> $apiUrl');

    final response = await _client.post(
      Uri.parse(apiUrl),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'messages': messages}),
    );

    if (response.statusCode != 200) {
      throw Exception(_extractError(response.body, response.statusCode));
    }

    final json = jsonDecode(response.body) as Map<String, dynamic>;
    final reply = (json['reply'] as String?)?.trim() ?? '';
    if (reply.isEmpty) {
      throw Exception('Empty response from the model.');
    }

    return ChatApiResponse(
      reply: reply,
      model: json['model'] as String? ?? '',
      promptTokens: _asInt(json['promptTokens']),
      completionTokens: _asInt(json['completionTokens']),
      totalTokens: _asInt(json['totalTokens']),
    );
  }

  static String _extractError(String body, int statusCode) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map<String, dynamic>) {
        final error = decoded['error'];
        if (error is String && error.isNotEmpty) return error;
        if (error is Map<String, dynamic>) {
          final message = error['message'];
          if (message is String && message.isNotEmpty) return message;
        }
      }
    } catch (_) {
      // not JSON — fall through
    }
    return 'Request failed ($statusCode)';
  }

  static int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.round();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0;
  }

  void dispose() => _client.close();
}
