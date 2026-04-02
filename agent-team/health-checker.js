function trimTrailingSlash(value) {
  return String(value || '').replace(/\/+$/, '');
}

function resolveApiKey(model, env = process.env) {
  const ref = model?.apiKeyRef;
  if (!ref) return '';
  return env[ref] || ref;
}

function buildOpenRouterRequest(model, apiKey) {
  return {
    method: 'POST',
    url: 'https://openrouter.ai/api/v1/chat/completions',
    headers: {
      'Content-Type': 'application/json',
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model: model.modelName,
      messages: [{ role: 'user', content: 'ping' }],
      max_tokens: 5,
      temperature: 0,
    }),
  };
}

function buildOpenAiCompatibleRequest(model, apiKey) {
  const baseUrl = trimTrailingSlash(model.baseUrl);
  return {
    method: 'GET',
    url: `${baseUrl}/models`,
    headers: {
      Authorization: `Bearer ${apiKey}`,
    },
  };
}

function buildAnthropicCompatibleRequest(model, apiKey) {
  const baseUrl = trimTrailingSlash(model.baseUrl);
  return {
    method: 'POST',
    url: `${baseUrl}/messages`,
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
    },
    body: JSON.stringify({
      model: model.modelName,
      messages: [{ role: 'user', content: 'ping' }],
      max_tokens: 5,
    }),
  };
}

function buildCheckRequest(model, env = process.env) {
  const apiKey = resolveApiKey(model, env);
  if (!apiKey) {
    throw new Error('No API key available');
  }

  if (model.provider === 'openrouter') {
    return buildOpenRouterRequest(model, apiKey);
  }

  if (model.provider === 'minimax' || /anthropic/i.test(model.baseUrl || '')) {
    return buildAnthropicCompatibleRequest(model, apiKey);
  }

  if (model.baseUrl) {
    return buildOpenAiCompatibleRequest(model, apiKey);
  }

  throw new Error(`Unsupported health check mode for provider: ${model.provider || 'unknown'}`);
}

async function checkModel(model, env = process.env, fetchImpl = fetch) {
  let request;
  try {
    request = buildCheckRequest(model, env);
  } catch (error) {
    return { ok: false, error: error.message, latency: 0 };
  }

  const start = Date.now();
  try {
    const res = await fetchImpl(request.url, {
      method: request.method || 'POST',
      headers: request.headers,
      body: request.body,
      signal: AbortSignal.timeout(20000),
    });
    const latency = Date.now() - start;

    if (res.ok) {
      return { ok: true, latency, status: res.status };
    }

    const text = await res.text().catch(() => '');
    const isModelNotFound = res.status === 404 || (res.status === 400 && text.includes('not found'));
    return {
      ok: false,
      error: `HTTP ${res.status}: ${text.slice(0, 200)}`,
      latency,
      status: res.status,
      isModelNotFound,
    };
  } catch (error) {
    return { ok: false, error: error.message, latency: Date.now() - start };
  }
}

module.exports = {
  resolveApiKey,
  buildCheckRequest,
  checkModel,
};
