// In development: use VITE_API_URL (defaults to localhost:8082)
// In production:  use the same origin (React is served by Spring Boot)
const BASE_URL = import.meta.env.VITE_API_URL || '';

/**
 * Send a conversation history to the backend and return the assistant's reply.
 * @param {Array<{role: string, content: string}>} messages
 * @returns {Promise<{reply: string, model: string, totalTokens: number}>}
 */
export async function sendMessage(messages) {
  const response = await fetch(`${BASE_URL}/api/chat`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ messages }),
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({}));
    throw new Error(err.error || `Request failed (${response.status})`);
  }

  return response.json();
}
