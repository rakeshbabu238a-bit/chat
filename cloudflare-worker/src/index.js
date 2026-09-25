/**
 * Cloudflare Worker — LLM proxy (OpenAI-compatible)
 *
 * Hosts `POST /chat` on Cloudflare's free plan (100k req/day, no card).
 * The LLM API key lives ONLY here as a Worker secret — it is never shipped
 * in the Flutter web bundle.
 *
 * Request  (POST /chat):  { "messages": [{ "role": "user", "content": "..." }] }
 * Response (200):         { reply, model, promptTokens, completionTokens, totalTokens }
 *
 * Secrets / vars (see wrangler.toml and `wrangler secret put`):
 *   LLM_API_KEY  (secret)  — your Gemini/OpenAI-compatible provider key
 *   LLM_MODEL    (var)     — optional, defaults to gemini-flash-latest
 *   LLM_API_URL  (var)     — optional, defaults to the Gemini OpenAI-compat URL
 *   ALLOW_ORIGIN (var)     — optional CORS origin, defaults to "*"
 */

const DEFAULT_API_URL =
  'https://generativelanguage.googleapis.com/v1beta/openai/chat/completions';
const DEFAULT_MODEL = 'gemini-flash-latest';
// Stable fallbacks tried (in order) when the primary model is overloaded
// (429/503). Keep to widely-available models the key supports.
const FALLBACK_MODELS = ['gemini-2.5-flash', 'gemini-2.5-flash-lite'];
const SYSTEM_PROMPT =
  'You are a helpful, concise, and friendly AI assistant. Answer questions clearly and accurately.';

function isTransient(status) {
  return status === 429 || status === 503;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function corsHeaders(env) {
  return {
    'Access-Control-Allow-Origin': env.ALLOW_ORIGIN || '*',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400',
  };
}

function json(body, status, env) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...corsHeaders(env) },
  });
}

export default {
  async fetch(request, env) {
    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: corsHeaders(env) });
    }

    const url = new URL(request.url);

    // Trim to defend against a trailing newline/space captured when the
    // secret was set — Gemini rejects "Bearer <key>\n" with a 401.
    const apiKey = (env.LLM_API_KEY || '').trim();
    if (!apiKey) {
      return json(
        { error: 'Server is missing LLM_API_KEY. Run: wrangler secret put LLM_API_KEY' },
        500,
        env,
      );
    }

    // Diagnostic: GET /models lists the model IDs the configured key supports.
    // Lets you confirm a valid LLM_MODEL without exposing the key anywhere.
    if (url.pathname === '/models' && request.method === 'GET') {
      const base = (env.LLM_API_URL || DEFAULT_API_URL).replace(
        '/chat/completions',
        '/models',
      );
      const r = await fetch(base, {
        headers: { Authorization: `Bearer ${apiKey}` },
      });
      const body = await r.text();
      return new Response(body, {
        status: r.status,
        headers: { 'Content-Type': 'application/json', ...corsHeaders(env) },
      });
    }

    if (url.pathname !== '/chat') {
      return json({ error: 'Not found' }, 404, env);
    }
    if (request.method !== 'POST') {
      return json({ error: 'Method not allowed' }, 405, env);
    }

    let messages;
    try {
      const parsed = await request.json();
      messages = parsed.messages;
    } catch {
      return json({ error: 'Invalid JSON body' }, 400, env);
    }
    if (!Array.isArray(messages) || messages.length === 0) {
      return json({ error: 'messages must be a non-empty array' }, 400, env);
    }

    const apiUrl = env.LLM_API_URL || DEFAULT_API_URL;
    const primary = env.LLM_MODEL || DEFAULT_MODEL;
    // Try the primary model first, then stable fallbacks (deduped).
    const models = [primary, ...FALLBACK_MODELS].filter(
      (m, i, arr) => m && arr.indexOf(m) === i,
    );

    const callModel = (model) =>
      fetch(apiUrl, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          Authorization: `Bearer ${apiKey}`,
        },
        body: JSON.stringify({
          model,
          messages: [{ role: 'system', content: SYSTEM_PROMPT }, ...messages],
          temperature: 0.7,
          max_tokens: 1024,
        }),
      });

    // Track the last transient failure so we can report it if everything fails.
    let lastStatus = 0;
    let lastBody = '';

    for (const model of models) {
      // Per-model retry with short backoff for transient 429/503.
      const maxAttempts = 3;
      for (let attempt = 1; attempt <= maxAttempts; attempt++) {
        let upstream;
        try {
          upstream = await callModel(model);
        } catch (err) {
          lastStatus = 502;
          lastBody = `Upstream request failed: ${err.message}`;
          if (attempt < maxAttempts) {
            await sleep(400 * attempt);
            continue;
          }
          break; // move to next model
        }

        if (upstream.ok) {
          const data = await upstream.json();
          const reply = data.choices?.[0]?.message?.content ?? '';
          const usage = data.usage || {};
          return json(
            {
              reply,
              model: data.model || model,
              promptTokens: usage.prompt_tokens || 0,
              completionTokens: usage.completion_tokens || 0,
              totalTokens: usage.total_tokens || 0,
            },
            200,
            env,
          );
        }

        // Not OK — record and decide whether to retry / fall through.
        lastStatus = upstream.status;
        lastBody = await upstream.text();

        if (isTransient(upstream.status) && attempt < maxAttempts) {
          await sleep(400 * attempt);
          continue; // retry same model
        }
        // Non-transient (e.g. 400/401): no point retrying or trying other
        // models with the same payload — stop and report.
        if (!isTransient(upstream.status)) {
          break;
        }
        // Transient and out of attempts for this model — try next model.
        break;
      }
    }

    // Everything failed. Surface the most useful message we have.
    let msg = `LLM request failed (${lastStatus || 502})`;
    try {
      const parsed = JSON.parse(lastBody);
      if (parsed?.error?.message) msg = parsed.error.message;
      else if (typeof parsed?.error === 'string') msg = parsed.error;
    } catch {
      if (lastBody) msg = `${msg}: ${lastBody.slice(0, 200)}`;
    }
    return json({ error: msg }, 502, env);
  },
};
