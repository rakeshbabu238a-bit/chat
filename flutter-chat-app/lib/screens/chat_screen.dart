import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/chat_input_bar.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _broadcastController = TextEditingController();
  bool _isSavingBroadcast = false;

  @override
  void initState() {
    super.initState();
    _resetBroadcast();
    // Save to Firestore on every change (live typing)
    _broadcastController.addListener(_onBroadcastChanged);
  }

  @override
  void dispose() {
    _broadcastController.removeListener(_onBroadcastChanged);
    _scrollController.dispose();
    _broadcastController.dispose();
    super.dispose();
  }

  Future<void> _loadBroadcast() async {
    final doc = await FirebaseFirestore.instance
        .collection('broadcast')
        .doc('current')
        .get();
    if (doc.exists) {
      final data = doc.data() as Map<String, dynamic>;
      _broadcastController.text = data['content'] as String? ?? '';
    }
  }

  /// Reset broadcast to empty on new session start.
  Future<void> _resetBroadcast() async {
    _broadcastController.clear();
    await FirebaseFirestore.instance.collection('broadcast').doc('current').set({
      'content': '',
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  // Debounce: write to Firestore after each keystroke with a small delay
  DateTime _lastWrite = DateTime.now();
  
  void _onBroadcastChanged() {
    final now = DateTime.now();
    _lastWrite = now;
    // Debounce 300ms to avoid hammering Firestore on fast typing
    Future.delayed(const Duration(milliseconds: 300), () {
      if (_lastWrite == now) {
        _saveBroadcast();
      }
    });
  }

  Future<void> _saveBroadcast() async {
    await FirebaseFirestore.instance.collection('broadcast').doc('current').set({
      'content': _broadcastController.text,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _confirmClear(BuildContext context, ChatProvider provider) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E293B),
        title: const Text('Clear chat?'),
        content: const Text('All messages will be deleted.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.clearChat();
      // Reset broadcast message for new session
      _broadcastController.clear();
      await _saveBroadcast();
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Consumer<ChatProvider>(
      builder: (context, provider, _) {
        if (provider.messages.isNotEmpty || provider.isLoading) {
          _scrollToBottom();
        }

        return Scaffold(
          backgroundColor: const Color(0xFF0F172A),
          appBar: _buildAppBar(context, provider, auth),
          body: Column(
            children: [
              // ── Broadcast text area (visible to readers) ──
              _buildBroadcastSection(),

              const Divider(color: Colors.white12, height: 1),

              // ── AI Chat (private — only admin sees this) ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                child: Row(
                  children: [
                    Icon(Icons.lock_outline, size: 14, color: Colors.white.withOpacity(0.3)),
                    const SizedBox(width: 6),
                    Text(
                      'Private AI Chat (not visible to readers)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.white.withOpacity(0.3),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _buildMessageList(provider),
              ),
              ChatInputBar(
                isLoading: provider.isLoading,
                onSend: (text) => provider.sendMessage(text),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBroadcastSection() {
    return Container(
      color: const Color(0xFF1E293B),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.campaign_outlined, size: 16, color: Colors.amber[300]),
              const SizedBox(width: 6),
              Text(
                'Live Broadcast to Readers',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.amber[300],
                ),
              ),
              const Spacer(),
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: Colors.greenAccent,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                'Live',
                style: TextStyle(fontSize: 10, color: Colors.white.withOpacity(0.4)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Container(
            constraints: const BoxConstraints(maxHeight: 100),
            decoration: BoxDecoration(
              color: const Color(0xFF0F172A),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.amber.withOpacity(0.2)),
            ),
            child: TextField(
              controller: _broadcastController,
              maxLines: null,
              style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.4),
              decoration: InputDecoration(
                hintText: 'Type here — readers see this live as you type…',
                hintStyle: TextStyle(color: Colors.white.withOpacity(0.3), fontSize: 13),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(
      BuildContext context, ChatProvider provider, AuthProvider auth) {
    return AppBar(
      backgroundColor: const Color(0xFF1E293B),
      elevation: 0,
      title: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF6366F1).withOpacity(0.2),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Center(
              child: Text('🤖', style: TextStyle(fontSize: 20)),
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'AI Chat',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
              Text(
                'Powered by Groq · Llama 3.3',
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.white.withOpacity(0.5),
                ),
              ),
            ],
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: provider.isLoading
              ? null
              : () => _confirmClear(context, provider),
          child: Text(
            'Clear',
            style: TextStyle(
              color: provider.isLoading
                  ? Colors.white30
                  : Colors.white.withOpacity(0.7),
            ),
          ),
        ),
        PopupMenuButton<String>(
          icon: CircleAvatar(
            radius: 16,
            backgroundColor: const Color(0xFF6366F1).withOpacity(0.3),
            child: Text(
              (auth.appUser?.displayName ?? 'U')[0].toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          color: const Color(0xFF1E293B),
          itemBuilder: (context) => [
            PopupMenuItem(
              enabled: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    auth.appUser?.displayName ?? '',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFF6366F1).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'Admin',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF818CF8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
            if (auth.isAdmin)
              const PopupMenuItem(
                value: 'admin',
                child: Row(
                  children: [
                    Icon(Icons.admin_panel_settings, size: 18, color: Color(0xFF818CF8)),
                    SizedBox(width: 8),
                    Text('Admin Panel', style: TextStyle(color: Colors.white)),
                  ],
                ),
              ),
            const PopupMenuItem(
              value: 'logout',
              child: Row(
                children: [
                  Icon(Icons.logout, size: 18, color: Colors.redAccent),
                  SizedBox(width: 8),
                  Text('Sign Out', style: TextStyle(color: Colors.redAccent)),
                ],
              ),
            ),
          ],
          onSelected: (value) {
            if (value == 'logout') {
              auth.signOut();
            } else if (value == 'admin') {
              Navigator.pushNamed(context, '/admin');
            }
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  Widget _buildMessageList(ChatProvider provider) {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      itemCount: provider.messages.length + (provider.isLoading ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == provider.messages.length) {
          return const TypingIndicator();
        }
        return MessageBubble(message: provider.messages[index]);
      },
    );
  }
}
