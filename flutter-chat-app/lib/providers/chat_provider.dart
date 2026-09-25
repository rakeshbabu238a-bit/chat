import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../services/chat_service.dart';
import '../services/chat_api_service.dart';

/// Central state manager for the chat screen.
///
/// Responsibilities:
/// - Own the active session ID
/// - Stream messages from Firestore (so the reader view stays in sync)
/// - Persist the user message, call the server-side `/chat` proxy (Cloudflare
///   Worker) for the reply, then persist the assistant reply. The LLM API key
///   lives only in the Worker and never reaches the client.
/// - Handle loading / error state
class ChatProvider extends ChangeNotifier {
  final ChatService _chatService;
  final ChatApiService _chatApi;
  final _uuid = const Uuid();

  ChatProvider(this._chatService, {ChatApiService? chatApi})
      : _chatApi = chatApi ?? ChatApiService() {
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

    // Seed the opening assistant greeting.
    final greeting = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.assistant,
      content: "Hi! I'm your AI assistant. How can I help you today?",
      timestamp: DateTime.now(),
    );
    await _chatService.addMessage(id, greeting);

    // Keep the local list in sync with Firestore so the reader view and the
    // admin view show the same messages.
    _messagesSub = _chatService.messagesStream(id).listen((msgs) {
      _messages = msgs;
      notifyListeners();
    });
  }

  // ── Public actions ───────────────────────────────────────────────────────

  /// Send a user message: persist it, call the `/chat` proxy for the reply,
  /// then persist the assistant reply (or an error bubble) to Firestore.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading || _sessionId == null) return;

    _setLoading(true);
    _error = null;

    final sessionId = _sessionId!;

    // 1. Persist the user message.
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: trimmed,
      timestamp: DateTime.now(),
    );

    // Build history including this new message (exclude error bubbles).
    final history = [
      ..._messages.where((m) => m.role != MessageRole.error),
      userMsg,
    ];

    final isFirstUserMessage =
        _messages.where((m) => m.role == MessageRole.user).isEmpty;

    try {
      await _chatService.addMessage(sessionId, userMsg);
      if (isFirstUserMessage) {
        await _chatService.updateSessionTitle(sessionId, trimmed);
      }

      // 2. Ask the server-side proxy for the reply.
      final result = await _chatApi.chat(history);

      // 3. Persist the assistant reply with token usage.
      final assistantMsg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.assistant,
        content: result.reply,
        timestamp: DateTime.now(),
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        totalTokens: result.totalTokens,
        model: result.model.isEmpty ? null : result.model,
      );
      await _chatService.addMessage(sessionId, assistantMsg);
    } catch (e) {
      // Persist an error bubble so the UI (and reader view) surface the failure.
      final errMsg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.error,
        content: e.toString().replaceFirst('Exception: ', ''),
        timestamp: DateTime.now(),
      );
      await _chatService.addMessage(sessionId, errMsg);
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
    _chatApi.dispose();
    super.dispose();
  }
}
