import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../services/chat_service.dart';

/// Central state manager for the chat screen.
///
/// Responsibilities:
/// - Own the active session ID
/// - Stream messages from Firestore
/// - Persist user messages (the server-side `onMessageCreated` Cloud Function
///   generates the assistant reply and writes it back to Firestore, which we
///   pick up via the stream — the LLM API key never reaches the client)
/// - Handle loading / error state
class ChatProvider extends ChangeNotifier {
  final ChatService _chatService;
  final _uuid = const Uuid();

  ChatProvider(this._chatService) {
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

    // Seed the opening assistant greeting. Role is `assistant`, so the
    // server-side trigger (which only fires on `user` messages) ignores it.
    final greeting = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.assistant,
      content: "Hi! I'm your AI assistant. How can I help you today?",
      timestamp: DateTime.now(),
    );
    await _chatService.addMessage(id, greeting);

    _messagesSub = _chatService.messagesStream(id).listen((msgs) {
      _messages = msgs;

      // Stop the "typing" indicator once the assistant (or an error) replies.
      if (_isLoading && msgs.isNotEmpty) {
        final last = msgs.last;
        if (last.role == MessageRole.assistant ||
            last.role == MessageRole.error) {
          _isLoading = false;
          if (last.role == MessageRole.error) _error = last.content;
        }
      }

      notifyListeners();
    });
  }

  // ── Public actions ───────────────────────────────────────────────────────

  /// Send a user message. The assistant reply is produced server-side by the
  /// `onMessageCreated` Cloud Function and streamed back via Firestore.
  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _isLoading || _sessionId == null) return;

    _setLoading(true);
    _error = null;

    // Persist the user message — this triggers the server-side reply.
    final userMsg = ChatMessage(
      id: _uuid.v4(),
      role: MessageRole.user,
      content: trimmed,
      timestamp: DateTime.now(),
    );

    // Update session title from the first user message
    final isFirstUserMessage =
        _messages.where((m) => m.role == MessageRole.user).isEmpty;

    try {
      await _chatService.addMessage(_sessionId!, userMsg);
      if (isFirstUserMessage) {
        await _chatService.updateSessionTitle(_sessionId!, trimmed);
      }
      // The assistant reply arrives asynchronously via messagesStream, which
      // clears the loading flag. Nothing else to do here.
    } catch (e) {
      // Failed to even persist the message — surface an error bubble.
      final errMsg = ChatMessage(
        id: _uuid.v4(),
        role: MessageRole.error,
        content: e.toString().replaceFirst('Exception: ', ''),
        timestamp: DateTime.now(),
      );
      await _chatService.addMessage(_sessionId!, errMsg);
      _error = errMsg.content;
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
    super.dispose();
  }
}
