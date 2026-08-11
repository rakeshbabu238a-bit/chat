import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:intl/intl.dart';

import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == MessageRole.user;
    final isError = message.role == MessageRole.error;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _Avatar(isError: isError),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                _Label(role: message.role),
                const SizedBox(height: 4),
                _Bubble(message: message, isUser: isUser, isError: isError),
                const SizedBox(height: 2),
                _Timestamp(timestamp: message.timestamp),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: 8),
            _Avatar(isUser: true),
          ],
        ],
      ),
    );
  }
}

// ── Sub-widgets ──────────────────────────────────────────────────────────────

class _Avatar extends StatelessWidget {
  final bool isUser;
  final bool isError;

  const _Avatar({this.isUser = false, this.isError = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: isUser
            ? const Color(0xFF6366F1)
            : isError
                ? Colors.redAccent.withOpacity(0.2)
                : const Color(0xFF334155),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Center(
        child: Text(
          isUser ? '👤' : isError ? '⚠️' : '🤖',
          style: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  final MessageRole role;

  const _Label({required this.role});

  @override
  Widget build(BuildContext context) {
    String label;
    Color color;
    switch (role) {
      case MessageRole.user:
        label = 'You';
        color = const Color(0xFF818CF8);
        break;
      case MessageRole.error:
        label = 'Error';
        color = Colors.redAccent;
        break;
      case MessageRole.assistant:
        label = 'Assistant';
        color = Colors.white54;
        break;
    }

    return Text(
      label,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: color,
        letterSpacing: 0.3,
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  final ChatMessage message;
  final bool isUser;
  final bool isError;

  const _Bubble({
    required this.message,
    required this.isUser,
    required this.isError,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _copyToClipboard(context, message.content),
      child: Container(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFF6366F1)
              : isError
                  ? const Color(0xFF450A0A)
                  : const Color(0xFF1E293B),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isError
              ? Border.all(color: Colors.redAccent.withOpacity(0.4))
              : null,
        ),
        child: isUser
            ? SelectableText(
                message.content,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
              )
            : MarkdownBody(
                data: message.content,
                styleSheet: _markdownStyleSheet(isError),
                selectable: true,
              ),
      ),
    );
  }

  MarkdownStyleSheet _markdownStyleSheet(bool isError) {
    final baseColor = isError ? Colors.red[200]! : Colors.white;
    return MarkdownStyleSheet(
      p: TextStyle(color: baseColor, fontSize: 14, height: 1.5),
      code: TextStyle(
        color: const Color(0xFF7DD3FC),
        backgroundColor: const Color(0xFF0F172A),
        fontSize: 13,
        fontFamily: 'monospace',
      ),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
      ),
      blockquote: TextStyle(
        color: Colors.white70,
        fontSize: 14,
        fontStyle: FontStyle.italic,
      ),
      h1: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 18),
      h2: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 16),
      h3: TextStyle(color: baseColor, fontWeight: FontWeight.bold, fontSize: 15),
      strong: TextStyle(color: baseColor, fontWeight: FontWeight.bold),
      em: TextStyle(color: baseColor, fontStyle: FontStyle.italic),
      listBullet: TextStyle(color: baseColor),
    );
  }

  void _copyToClipboard(BuildContext context, String text) {
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Message copied to clipboard'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

class _Timestamp extends StatelessWidget {
  final DateTime timestamp;

  const _Timestamp({required this.timestamp});

  @override
  Widget build(BuildContext context) {
    return Text(
      DateFormat('HH:mm').format(timestamp),
      style: const TextStyle(
        fontSize: 10,
        color: Colors.white38,
      ),
    );
  }
}
