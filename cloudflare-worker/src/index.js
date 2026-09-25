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
// (503). Bare model IDs — the OpenAI-compat chat endpoint accepts these
// (e.g. gemini-flash-latest worked without a prefix).
const FALLBACK_MODELS = ['gemini-2.5-flash', 'gemini-flash-latest'];
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
function upstreamError(status, rawBody, env) {
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
  return json({ error: msg }, status === 429 ? 429 : 502, env);
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
    let requestedModel;
    try {
      const parsed = await request.json();
      messages = parsed.messages;
      requestedModel = parsed.model; // optional debug/override
    } catch {
      return json({ error: 'Invalid JSON body' }, 400, env);
    }
    if (!Array.isArray(messages) || messages.length === 0) {
      return json({ error: 'messages must be a non-empty array' }, 400, env);
    }

    const apiUrl = env.LLM_API_URL || DEFAULT_API_URL;
    const primary = env.LLM_MODEL || DEFAULT_MODEL;
    // If the caller supplied a model, use only that (debug/override).
    // Otherwise try the primary then fallbacks (deduped).
    const models = requestedModel
      ? [requestedModel]
      : [primary, ...FALLBACK_MODELS].filter(
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

        if (isRetryable(upstream.status) && attempt < maxAttempts) {
          await sleep(400 * attempt);
          continue; // retry same model on 503 (overloaded)
        }
        // 429 (quota) or 4xx: retrying/falling back wastes quota and won't
        // help. Stop immediately and report the upstream error.
        if (!isRetryable(upstream.status)) {
          return upstreamError(lastStatus, lastBody, env);
        }
        // 503 and out of attempts for this model — try the next model.
        break;
      }
    }

    // Everything failed (all models 503'd through their retries).
    return upstreamError(lastStatus || 502, lastBody, env);
  },
};
