import 'package:cloud_firestore/cloud_firestore.dart';

/// Mirrors the role values used by the Groq / OpenAI API.
enum MessageRole { user, assistant, error }

class ChatMessage {
  final String id;
  final MessageRole role;
  final String content;
  final DateTime timestamp;

  /// Optional token usage — populated on assistant messages.
  final int? promptTokens;
  final int? completionTokens;
  final int? totalTokens;
  final String? model;

  const ChatMessage({
    required this.id,
    required this.role,
    required this.content,
    required this.timestamp,
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
    this.model,
  });

  // ── Firestore serialisation ──────────────────────────────────────────────

  factory ChatMessage.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return ChatMessage(
      id: doc.id,
      role: _roleFromString(data['role'] as String? ?? 'user'),
      content: data['content'] as String? ?? '',
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      promptTokens: data['promptTokens'] as int?,
      completionTokens: data['completionTokens'] as int?,
      totalTokens: data['totalTokens'] as int?,
      model: data['model'] as String?,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'role': role.name,
      'content': content,
      'timestamp': Timestamp.fromDate(timestamp),
      if (promptTokens != null) 'promptTokens': promptTokens,
      if (completionTokens != null) 'completionTokens': completionTokens,
      if (totalTokens != null) 'totalTokens': totalTokens,
      if (model != null) 'model': model,
    };
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  /// Convert to the format the Groq / OpenAI API expects.
  Map<String, String> toApiMessage() => {
        'role': role == MessageRole.error ? 'user' : role.name,
        'content': content,
      };

  static MessageRole _roleFromString(String value) {
    switch (value) {
      case 'assistant':
        return MessageRole.assistant;
      case 'error':
        return MessageRole.error;
      default:
        return MessageRole.user;
    }
  }

  @override
  String toString() => 'ChatMessage(role: ${role.name}, content: $content)';
}
