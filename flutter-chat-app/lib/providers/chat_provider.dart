import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../services/groq_service.dart';
import '../config/app_config.dart';

/// Central state manager for the chat screen.
///
/// Responsibilities:
/// - Own the active session ID
/// - Stream messages from Firestore
/// - Send user messages and trigger Groq replies
/// - Handle loading / error state
class ChatProvider extends ChangeNotifier {
  final ChatService _chatService;
  late final GroqService _groqService;
  final _uuid = const Uuid();

  ChatProvider(this._chatService) {
    _groqService = GroqService(apiKey: AppConfig.groqApiKey);
    _init();
  }

  // ── State ────────────────────────────────────────────────────────────────

  String? _sessionId;
  List<ChatMessage> _messages = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription<List<ChatMessage>>? _messagesSub;

  String? get sessionId => _sessionId;
  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get isLoading => _isLoading;
  String? get error => _error;

  // ── Initialisation ───────────────────────────────────────────────────────

  Future<void> _init() async {
    await _startNewSession();
  }

  Future<void> _startNewSession() async {
    _messagesSub?.cancel();

    final id = await _chatService.createSession();
    _sessionId = id;

    // Seed the opening assistant greeting (not persisted to API history)
    final greeting = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.assistant,
      content: "Hi! I'm your AI assistant. How can I help you today?",
      timestamp: DateTime.now(),
    );
    await _chatService.addMessage(id, greeting);

    _messagesSub = _chatService.messagesStream(id).listen((msgs) {
      _messages = msgs;
      notifyListeners();
    });
  }

  // ── Public actions ───────────────────────────────────────────────────────

  /// Send a user message and fetch the assistant reply.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading || _sessionId == null) return;

    _setLoading(true);
    _error = null;

    // 1. Persist the user message
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: trimmed,
      timestamp: DateTime.now(),
    );
    await _chatService.addMessage(_sessionId!, userMsg);

    // Update session title from the first user message
    final isFirstUserMessage =
        _messages.where((m) => m.role == MessageRole.user).length == 1;
    if (isFirstUserMessage) {
      await _chatService.updateSessionTitle(_sessionId!, trimmed);
    }

    try {
      // 2. Build conversation history (exclude error bubbles)
      final history = _messages
          .where((m) => m.role != MessageRole.error)
          .toList();

      // 3. Call Groq
      final result = await _groqService.chat(history);

      // 4. Persist the assistant reply with token usage
      final assistantMsg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: result.reply,
        timestamp: DateTime.now(),
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        totalTokens: result.totalTokens,
        model: result.model,
      );
      await _chatService.addMessage(_sessionId!, assistantMsg);
    } catch (e) {
      // 5. Persist an error bubble so the UI stays consistent
      final errMsg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.error,
        content: e.toString().replaceFirst('Exception: ', ''),
        timestamp: DateTime.now(),
      );
      await _chatService.addMessage(_sessionId!, errMsg);
      _error = errMsg.content;
    } finally {
      _setLoading(false);
    }
  }

  /// Clears all messages and resets the session title.
  Future<void> clearChat() async {
    if (_sessionId == null) return;
    await _chatService.clearMessages(_sessionId!);

    // Re-seed the greeting after clear
    final greeting = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.assistant,
      content: 'Chat cleared. How can I help you?',
      timestamp: DateTime.now(),
    );
    await _chatService.addMessage(_sessionId!, greeting);
  }

  // ── Private helpers ──────────────────────────────────────────────────────

  void _setLoading(bool value) {
    _isLoading = value;
    notifyListeners();
  }

  @override
  void dispose() {
    _messagesSub?.cancel();
    _groqService.dispose();
    super.dispose();
  }
}
