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
// (503). Only add IDs confirmed callable on this key's tier — models can
// appear in GET /models yet 404 on the chat endpoint. Left empty by default
// so we rely on the proven primary (gemini-flash-latest).
const FALLBACK_MODELS = [];
const SYSTEM_PROMPT =
  'You are a helpful, concise, and friendly AI assistant. Answer questions clearly and accurately.';

// 503 = overloaded (safe to retry/fall back). 429 = quota exhausted, where
// retrying or trying other models just burns more of the (tiny) free quota,
// so we surface it immediately instead.
function isRetryable(status) {
  return status === 503;
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

// Build a clean error Response from a failed upstream reply, given the
// already-read status and body text (the body stream can only be read once).
function upstreamError(status, rawBody, cors) {
  let msg = `LLM request failed (${status})`;
  try {
    const parsed = JSON.parse(rawBody);
    if (parsed?.error?.message) msg = parsed.error.message;
    else if (typeof parsed?.error === 'string') msg = parsed.error;
  } catch {
    if (rawBody) msg = `${msg}: ${rawBody.slice(0, 200)}`;
  }
  if (status === 429) {
    msg =
      'The AI is rate-limited right now (free-tier quota reached). ' +
      'Please wait a minute and try again.';
  }
  return json({ error: msg }, status === 429 ? 429 : 502, cors);
}

// Resolve CORS headers for this request. ALLOW_ORIGIN may be a single origin,
// a comma-separated allowlist, or "*". When it's an allowlist, echo back the
// request's Origin only if it matches.
function corsHeaders(request, env) {
  const configured = (env.ALLOW_ORIGIN || '*').trim();
  let allowOrigin = configured;
  if (configured !== '*') {
    const allowed = configured.split(',').map((o) => o.trim());
    const origin = request.headers.get('Origin');
    // Default to the first configured origin (non-browser callers send no
    // Origin); echo the request origin when it's in the allowlist.
    allowOrigin = origin && allowed.includes(origin) ? origin : allowed[0];
  }
  return {
    'Access-Control-Allow-Origin': allowOrigin,
    Vary: 'Origin',
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type',
    'Access-Control-Max-Age': '86400',
  };
}

function json(body, status, cors) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json', ...cors },
  });
}

export default {
  async fetch(request, env) {
    const cors = corsHeaders(request, env);

    // CORS preflight
    if (request.method === 'OPTIONS') {
      return new Response(null, { status: 204, headers: cors });
    }

    const url = new URL(request.url);

    // Trim to defend against a trailing newline/space captured when the
    // secret was set — Gemini rejects "Bearer <key>\n" with a 401.
    const apiKey = (env.LLM_API_KEY || '').trim();
    if (!apiKey) {
      return json(
        { error: 'Server is missing LLM_API_KEY. Run: wrangler secret put LLM_API_KEY' },
        500,
        cors,
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
        headers: { 'Content-Type': 'application/json', ...cors },
      });
    }

    if (url.pathname !== '/chat') {
      return json({ error: 'Not found' }, 404, cors);
    }
    if (request.method !== 'POST') {
      return json({ error: 'Method not allowed' }, 405, cors);
    }

    let messages;
    try {
      const parsed = await request.json();
      messages = parsed.messages;
    } catch {
      return json({ error: 'Invalid JSON body' }, 400, cors);
    }
    if (!Array.isArray(messages) || messages.length === 0) {
      return json({ error: 'messages must be a non-empty array' }, 400, cors);
    }

    const apiUrl = env.LLM_API_URL || DEFAULT_API_URL;
    const primary = env.LLM_MODEL || DEFAULT_MODEL;
    // Try the primary model first, then stable fallbacks (deduped).
    // The client cannot choose the model — it's server-controlled.
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
            cors,
          );
        }

        // Not OK — record and decide whether to retry / fall through.
        lastStatus = upstream.status;
        lastBody = await upstream.text();

        if (isRetryable(upstream.status) && attempt < maxAttempts) {
          await sleep(400 * attempt);
          continue; // retry same model on 503 (overloaded)
        }
        // 429 (quota) or 4xx: retrying/falling back wastes quota and won't
        // help. Stop immediately and report the upstream error.
        if (!isRetryable(upstream.status)) {
          return upstreamError(lastStatus, lastBody, cors);
        }
        // 503 and out of attempts for this model — try the next model.
        break;
      }
    }

    // Everything failed (all models 503'd through their retries).
    return upstreamError(lastStatus || 502, lastBody, cors);
  },
};
