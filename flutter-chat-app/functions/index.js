/**
 * Firebase Cloud Functions — Groq LLM proxy
 *
 * This function exposes two interfaces:
 *
 * 1. HTTP endpoint  POST /chat
 *    Accepts { messages: [{role, content}] }
 *    Returns  { reply, model, promptTokens, completionTokens, totalTokens }
 *
 * 2. Firestore trigger  onCreate chatSessions/{sessionId}/messages/{messageId}
 *    When a "user" role message is written, automatically calls Groq and
 *    writes the assistant reply back to the same sub-collection.
 *
 * Environment variables (set with `firebase functions:secrets:set GROQ_API_KEY`):
 *   GROQ_API_KEY  — your Groq API key
 *   GROQ_MODEL    — optional, defaults to llama-3.3-70b-versatile
 */

const { onRequest } = require('firebase-functions/v2/https');
const { onDocumentCreated } = require('firebase-functions/v2/firestore');
const { defineSecret } = require('firebase-functions/params');
const { initializeApp } = require('firebase-admin/app');
const { getFirestore, Timestamp } = require('firebase-admin/firestore');
const { getAuth } = require('firebase-admin/auth');
const { randomUUID } = require('crypto');

initializeApp();

const GROQ_API_KEY = defineSecret('GROQ_API_KEY');
const GROQ_API_URL = 'https://api.groq.com/openai/v1/chat/completions';
const DEFAULT_MODEL = 'llama-3.3-70b-versatile';
const SYSTEM_PROMPT =
  'You are a helpful, concise, and friendly AI assistant. Answer questions clearly and accurately.';

// ── Shared Groq call ─────────────────────────────────────────────────────────

async function callGroq(messages, apiKey) {
  const model = process.env.GROQ_MODEL || DEFAULT_MODEL;

  const payload = {
    model,
    messages: [{ role: 'system', content: SYSTEM_PROMPT }, ...messages],
    temperature: 0.7,
    max_tokens: 1024,
  };

  // node-fetch v3 is ESM-only; we use dynamic import for CJS compat
  const { default: fetch } = await import('node-fetch');

  const response = await fetch(GROQ_API_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(payload),
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({}));
    const msg = err?.error?.message || `Groq request failed (${response.status})`;
    throw new Error(msg);
  }

  const data = await response.json();
  const reply = data.choices[0].message.content;
  const usage = data.usage;
  const usedModel = data.model || model;

  return {
    reply,
    model: usedModel,
    promptTokens: usage.prompt_tokens,
    completionTokens: usage.completion_tokens,
    totalTokens: usage.total_tokens,
  };
}

// ── 1. HTTP endpoint ─────────────────────────────────────────────────────────

exports.chat = onRequest(
  {
    secrets: [GROQ_API_KEY],
    cors: true,           // allow all origins; tighten for production
    timeoutSeconds: 60,
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const { messages } = req.body;
    if (!Array.isArray(messages) || messages.length === 0) {
      res.status(400).json({ error: 'messages must be a non-empty array' });
      return;
    }

    try {
      const result = await callGroq(messages, GROQ_API_KEY.value());
      res.status(200).json(result);
    } catch (err) {
      console.error('[chat] Groq error:', err.message);
      res.status(502).json({ error: err.message });
    }
  }
);

// ── 2. Firestore trigger ─────────────────────────────────────────────────────

exports.onMessageCreated = onDocumentCreated(
  {
    document: 'chatSessions/{sessionId}/messages/{messageId}',
    secrets: [GROQ_API_KEY],
    timeoutSeconds: 60,
  },
  async (event) => {
    const data = event.data?.data();
    if (!data) return;

    // Only react to user messages
    if (data.role !== 'user') return;

    const { sessionId } = event.params;
    const db = getFirestore();
    const messagesRef = db
      .collection('chatSessions')
      .doc(sessionId)
      .collection('messages');

    // Fetch full conversation history, ordered by timestamp
    const snap = await messagesRef.orderBy('timestamp').get();
    const history = snap.docs
      .map((d) => d.data())
      .filter((m) => m.role === 'user' || m.role === 'assistant')
      .map((m) => ({ role: m.role, content: m.content }));

    try {
      const result = await callGroq(history, GROQ_API_KEY.value());

      const assistantDoc = {
        role: 'assistant',
        content: result.reply,
        timestamp: Timestamp.now(),
        model: result.model,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        totalTokens: result.totalTokens,
      };

      // Write assistant reply to Firestore — Flutter client picks it up via stream
      await messagesRef.doc(randomUUID()).set(assistantDoc);

      // Keep session updatedAt fresh
      await db.collection('chatSessions').doc(sessionId).update({
        updatedAt: Timestamp.now(),
      });

      console.log(
        `[onMessageCreated] Reply written for session=${sessionId} tokens=${result.totalTokens}`
      );
    } catch (err) {
      console.error('[onMessageCreated] Groq error:', err.message);

      // Write an error bubble so the Flutter UI surfaces the failure
      await messagesRef.doc(randomUUID()).set({
        role: 'error',
        content: err.message,
        timestamp: Timestamp.now(),
      });
    }
  }
);


// ── 3. Delete user (Auth + Firestore) ────────────────────────────────────────

exports.deleteUser = onRequest(
  {
    cors: true,
    timeoutSeconds: 30,
  },
  async (req, res) => {
    if (req.method !== 'POST') {
      res.status(405).json({ error: 'Method not allowed' });
      return;
    }

    const { uid } = req.body;
    if (!uid) {
      res.status(400).json({ error: 'uid is required' });
      return;
    }

    try {
      // Delete from Firebase Auth
      await getAuth().deleteUser(uid);
      console.log(`[deleteUser] Deleted Auth user: ${uid}`);
    } catch (err) {
      // User might not exist in Auth — that's okay, continue
      console.warn(`[deleteUser] Auth delete failed for ${uid}: ${err.message}`);
    }

    try {
      // Delete from Firestore
      await getFirestore().collection('users').doc(uid).delete();
      console.log(`[deleteUser] Deleted Firestore profile: ${uid}`);
    } catch (err) {
      console.warn(`[deleteUser] Firestore delete failed for ${uid}: ${err.message}`);
    }

    res.status(200).json({ success: true, message: `User ${uid} deleted` });
  }
);
