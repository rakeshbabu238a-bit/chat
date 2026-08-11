import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_message.dart';
import '../models/chat_session.dart';

/// Handles all Firestore reads/writes for chat sessions and messages.
///
/// Firestore schema:
///   chatSessions (collection)
///     └─ {sessionId} (document)
///          ├─ title, createdAt, updatedAt
///          └─ messages (sub-collection)
///               └─ {messageId} (document)
///                    ├─ role, content, timestamp
///                    └─ [promptTokens, completionTokens, totalTokens, model]
class ChatService {
  final FirebaseFirestore _db;
  final _uuid = const Uuid();

  ChatService({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  // ── Collection references ────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> get _sessions =>
      _db.collection('chatSessions');

  CollectionReference<Map<String, dynamic>> _messages(String sessionId) =>
      _sessions.doc(sessionId).collection('messages');

  // ── Session management ───────────────────────────────────────────────────

  /// Creates a new chat session and returns its ID.
  Future<String> createSession() async {
    final now = DateTime.now();
    final doc = await _sessions.add({
      'title': 'New Chat',
      'createdAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
    return doc.id;
  }

  /// Updates the session title (uses the first user message).
  Future<void> updateSessionTitle(String sessionId, String title) async {
    await _sessions.doc(sessionId).update({
      'title': title.length > 50 ? '${title.substring(0, 47)}…' : title,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Deletes an entire session and all its messages.
  Future<void> deleteSession(String sessionId) async {
    // Delete all messages in the sub-collection first
    final msgs = await _messages(sessionId).get();
    final batch = _db.batch();
    for (final doc in msgs.docs) {
      batch.delete(doc.reference);
    }
    batch.delete(_sessions.doc(sessionId));
    await batch.commit();
  }

  /// Stream of all sessions, ordered newest first.
  Stream<List<ChatSession>> sessionsStream() {
    return _sessions
        .orderBy('updatedAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ChatSession.fromFirestore(d)).toList());
  }

  // ── Message management ───────────────────────────────────────────────────

  /// Writes a single message to Firestore and returns its ID.
  Future<String> addMessage(String sessionId, ChatMessage message) async {
    final msgId = _uuid.v4();
    await _messages(sessionId).doc(msgId).set(message.toFirestore());

    // Keep updatedAt fresh on the session
    await _sessions.doc(sessionId).update({
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });

    return msgId;
  }

  /// Real-time stream of messages for a session, ordered by timestamp.
  Stream<List<ChatMessage>> messagesStream(String sessionId) {
    return _messages(sessionId)
        .orderBy('timestamp')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => ChatMessage.fromFirestore(d)).toList());
  }

  /// One-time fetch of all messages (used to build the API history payload).
  Future<List<ChatMessage>> getMessages(String sessionId) async {
    final snap =
        await _messages(sessionId).orderBy('timestamp').get();
    return snap.docs.map((d) => ChatMessage.fromFirestore(d)).toList();
  }

  /// Deletes all messages in a session (clear chat without deleting session).
  Future<void> clearMessages(String sessionId) async {
    final msgs = await _messages(sessionId).get();
    final batch = _db.batch();
    for (final doc in msgs.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    // Reset session title
    await _sessions.doc(sessionId).update({
      'title': 'New Chat',
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }
}
