const test = require('node:test');
const assert = require('node:assert/strict');

const {
  resolveApiKey,
  buildCheckRequest,
} = require('./health-checker');

test('OpenRouter model uses OpenRouter endpoint and env var key', () => {
  const model = {
    provider: 'openrouter',
    modelName: 'xiaomi/mimo-v2-pro',
    apiKeyRef: 'OPENROUTER_API_KEY',
  };

  const req = buildCheckRequest(model, {
    OPENROUTER_API_KEY: 'sk-or-test',
  });

  assert.equal(req.url, 'https://openrouter.ai/api/v1/chat/completions');
  assert.equal(req.headers.Authorization, 'Bearer sk-or-test');
  assert.equal(JSON.parse(req.body).model, 'xiaomi/mimo-v2-pro');
});

test('OpenAI-compatible proxy uses model baseUrl and direct key string', () => {
  const model = {
    provider: 'openai',
    modelName: 'gpt-5.4',
    baseUrl: 'https://aixj.vip/v1',
    apiKeyRef: 'sk-proxy-direct-key',
  };

  const req = buildCheckRequest(model, {});

  assert.equal(req.method, 'GET');
  assert.equal(req.url, 'https://aixj.vip/v1/models');
  assert.equal(req.headers.Authorization, 'Bearer sk-proxy-direct-key');
  assert.equal(req.body, undefined);
});

test('resolveApiKey supports env var names and direct keys', () => {
  assert.equal(
    resolveApiKey({ apiKeyRef: 'OPENROUTER_API_KEY' }, { OPENROUTER_API_KEY: 'env-key' }),
    'env-key'
  );
  assert.equal(
    resolveApiKey({ apiKeyRef: 'sk-direct-key' }, {}),
    'sk-direct-key'
  );
});
