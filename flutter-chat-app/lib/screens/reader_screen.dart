import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';

/// Reader view — shows the admin's broadcast message in real-time.
class ReaderScreen extends StatelessWidget {
  const ReaderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();

    return Scaffold(
      backgroundColor: const Color(0xFF0F172A),
      appBar: _buildAppBar(context, auth),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('broadcast')
          .doc('current')
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: Color(0xFF6366F1)),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Error: ${snapshot.error}',
              style: const TextStyle(color: Colors.redAccent),
            ),
          );
        }

        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final content = data?['content'] as String? ?? '';
        final updatedAt = (data?['updatedAt'] as Timestamp?)?.toDate();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Broadcast section — only show if there's content
              if (content.isNotEmpty) ...[
              // Header
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Center(
                      child: Text('📡', style: TextStyle(fontSize: 18)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Admin Broadcast',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                      if (updatedAt != null)
                        Text(
                          _formatTime(updatedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white.withOpacity(0.4),
                          ),
                        ),
                    ],
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
                  const SizedBox(width: 6),
                  Text(
                    'Live',
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.white.withOpacity(0.4),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Broadcast content
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.amber.withOpacity(0.1),
                  ),
                ),
                child: MarkdownBody(
                  data: content,
                  selectable: true,
                  styleSheet: _markdownStyle(),
                ),
              ),
              const SizedBox(height: 24),
              ],

              // AI Response section (always visible)
              _AIResponseCard(),
            ],
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, AuthProvider auth) {
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
        PopupMenuButton<String>(
          icon: CircleAvatar(
            radius: 16,
            backgroundColor: Colors.amber.withOpacity(0.3),
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
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      'Reader',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber[300],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const PopupMenuDivider(),
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
            }
          },
        ),
        const SizedBox(width: 8),
      ],
    );
  }

  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }

  MarkdownStyleSheet _markdownStyle() {
    return MarkdownStyleSheet(
      p: const TextStyle(color: Colors.white, fontSize: 15, height: 1.7),
      code: const TextStyle(
        color: Color(0xFF7DD3FC),
        backgroundColor: Color(0xFF0F172A),
        fontSize: 13,
        fontFamily: 'monospace',
      ),
      codeblockDecoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(8),
      ),
      h1: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
      h2: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
      h3: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
      strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
      em: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic),
      listBullet: const TextStyle(color: Colors.white),
    );
  }
}

// ── AI Response Card (latest assistant message) ──────────────────────────────

class _AIResponseCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collectionGroup('messages')
          .where('role', isEqualTo: 'assistant')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(color: Color(0xFF6366F1))),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final data = snapshot.data!.docs.first.data() as Map<String, dynamic>;
        final content = data['content'] as String? ?? '';
        final model = data['model'] as String? ?? 'AI';
        final timestamp = (data['timestamp'] as Timestamp?)?.toDate();

        // Skip the initial greeting message
        if (content.contains("Hi! I'm your AI assistant") || content.contains('Chat cleared')) {
          return const SizedBox.shrink();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: const Color(0xFF334155),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Center(
                    child: Text('🤖', style: TextStyle(fontSize: 16)),
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AI Response',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.white70,
                      ),
                    ),
                    if (timestamp != null)
                      Text(
                        _formatTimeStatic(timestamp),
                        style: TextStyle(
                          fontSize: 10,
                          color: Colors.white.withOpacity(0.4),
                        ),
                      ),
                  ],
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    model,
                    style: const TextStyle(fontSize: 10, color: Color(0xFF818CF8)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: MarkdownBody(
                data: content,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(color: Colors.white, fontSize: 14, height: 1.6),
                  code: const TextStyle(
                    color: Color(0xFF7DD3FC),
                    backgroundColor: Color(0xFF0F172A),
                    fontSize: 13,
                    fontFamily: 'monospace',
                  ),
                  codeblockDecoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  h1: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
                  h2: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                  h3: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
                  strong: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  em: const TextStyle(color: Colors.white, fontStyle: FontStyle.italic),
                  listBullet: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  static String _formatTimeStatic(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${dt.day}/${dt.month}/${dt.year} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
