/**
 * Agent Team - 模型健康监控服务
 *
 * 职责：
 *  1. 定期检测模型池中每个模型的可用性
 *  2. 模型异常时，根据 Agent 角色 + 模型特征，自动选择最优替代
 *  3. 模型恢复后，自动将 Agent 切回原始模型
 *  4. 提供 API 供 UI 查询健康状态
 *
 * 使用：
 *  node agent-team/health-monitor.js
 *  或由 server.js 以子进程方式启动
 */

const http = require('http');
const fs = require('fs');
const path = require('path');

const WORKSPACE = process.env.WORKSPACE || '/home/node/.openclaw/workspace';
const CONFIG_FILE = path.join(WORKSPACE, 'agent-team', 'config.json');
const STATE_FILE  = path.join(WORKSPACE, 'agent-team', 'health-state.json');
const LOG_FILE    = path.join(WORKSPACE, 'agent-team', 'health-log.json');

// ─── 工具函数 ───

function readJson(file, fallback) {
  try { return JSON.parse(fs.readFileSync(file, 'utf8')); }
  catch { return fallback; }
}

function writeJson(file, data) {
  fs.writeFileSync(file, JSON.stringify(data, null, 2), 'utf8');
}

function now() { return Date.now(); }

function ts() { return new Date().toISOString().replace('T',' ').slice(0,19); }

// ─── 状态管理 ───

let config = readJson(CONFIG_FILE, {});
let state  = readJson(STATE_FILE, { models: {}, overrides: {}, stats: { totalChecks: 0, totalFails: 0, totalSwitches: 0 } });
let log    = readJson(LOG_FILE, []);

function addLog(type, message, meta) {
  const entry = { time: ts(), type, message, ...(meta || {}) };
  log.unshift(entry);
  if (log.length > 500) log.length = 500;
  writeJson(LOG_FILE, log);
}

// ─── 模型检测 ───

/**
 * 检测单个模型是否可用
 * 通过 OpenRouter（OpenAI 兼容）的 chat/completions 发送极简请求
 * 优先使用模型自己的 apiKeyRef，回退到 OpenRouter
 */
async function checkModel(model) {
  // 优先用模型自己的 key，其次回退到 OpenRouter
  const apiKey = process.env[model.apiKeyRef] || process.env.OPENROUTER_API_KEY;
  if (!apiKey) return { ok: false, error: 'No API key available', latency: 0 };

  // OpenRouter 作为统一入口
  const url = 'https://openrouter.ai/api/v1/chat/completions';

  const body = JSON.stringify({
    model: model.modelName,
    messages: [{ role: 'user', content: 'ping' }],
    max_tokens: 5,
    temperature: 0,
  });

  const start = now();
  try {
    const res = await fetch(url, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${apiKey}`,
      },
      body,
      signal: AbortSignal.timeout(20000),
    });
    const latency = now() - start;

    if (res.ok) {
      return { ok: true, latency, status: res.status };
    } else {
      const text = await res.text().catch(() => '');
      // 404/400 可能是模型名在 OpenRouter 上不存在，记为 warning 而非 error
      const isModelNotFound = res.status === 404 || (res.status === 400 && text.includes('not found'));
      return { ok: false, error: `HTTP ${res.status}: ${text.slice(0,200)}`, latency, status: res.status, isModelNotFound };
    }
  } catch (e) {
    return { ok: false, error: e.message, latency: now() - start };
  }
}

function getDefaultBaseUrl(provider) {
  const map = {
    openai:      'https://api.openai.com/v1',
    anthropic:   'https://api.anthropic.com/v1',
    deepseek:    'https://api.deepseek.com/v1',
    moonshot:    'https://api.moonshot.cn/v1',
    minimax:     'https://api.minimax.chat/v1',
    zhipu:       'https://open.bigmodel.cn/api/paas/v4',
    qwen:        'https://dashscope.aliyuncs.com/compatible-mode/v1',
    siliconflow: 'https://api.siliconflow.cn/v1',
    groq:        'https://api.groq.com/openai/v1',
    mistral:     'https://api.mistral.ai/v1',
    google:      'https://generativelanguage.googleapis.com/v1beta/openai',
    openrouter:  'https://openrouter.ai/api/v1',
  };
  return map[provider] || '';
}

// ─── 健康判断 ───

function isModelHealthy(modelId) {
  const s = state.models[modelId];
  if (!s) return true; // 从未检测过，默认健康
  return s.status === 'up';
}

// ─── 智能故障转移 ───

/**
 * 角色 → 需要的能力标签映射
 */
const ROLE_PREFERENCES = {
  coordinator: ['chat', 'daily', 'coding', 'reasoning', 'creative'],
  memory:      ['chat', 'daily'],
  skills:      ['coding', 'reasoning', 'analysis'],
  execution:   ['coding', 'daily', 'analysis'],
  review:      ['reasoning', 'analysis', 'coding'],
  coding:      ['coding', 'reasoning'],
  design:      ['creative', 'coding'],
  daily:       ['chat', 'daily'],
  group:       ['chat', 'daily'],
  research:    ['reasoning', 'analysis'],
};

/**
 * 成本等级排序
 */
const COST_RANK = { premium: 3, standard: 2, economy: 1 };

/**
 * 为指定 Agent 从模型池中选择最佳替代模型
 * 排除当前不可用的模型
 */
function findBestFallback(agentId, failedModelName) {
  const agent = config.agents?.[agentId];
  if (!agent) return null;

  const models = config.models || [];
  const role = agent.role || 'daily';
  const prefs = ROLE_PREFERENCES[role] || ['chat', 'daily'];
  const maxTier = COST_RANK[agent.preferredCostTier || 'standard'] || 2;

  // 候选池：健康 + 不是失败的那个
  const candidates = models.filter(m =>
    m.modelName !== failedModelName &&
    isModelHealthy(m.modelName)
  );

  if (candidates.length === 0) return null;

  // 打分
  const scored = candidates.map(m => {
    let score = 0;
    // 能力匹配
    const tags = m.tags || [];
    prefs.forEach((pref, i) => {
      if (tags.includes(pref)) score += (prefs.length - i) * 2;
    });
    // 成本匹配（不超过 Agent 偏好等级）
    const tier = COST_RANK[m.costTier] || 2;
    if (tier <= maxTier) score += 3;
    else score -= 2;
    // Agent 自己的 fallback 列表里有的加分
    if ((agent.fallbackModels || []).includes(m.modelName)) score += 5;
    return { model: m, score };
  });

  scored.sort((a, b) => b.score - a.score);
  return scored[0]?.model || null;
}

/**
 * 故障转移：将 Agent 从失败模型切换到替代模型
 */
function switchAgent(agentId, failedModel, fallbackModel, reason) {
  if (!state.overrides) state.overrides = {};

  const existing = state.overrides[agentId];
  // 如果已经在 override 状态，更新
  state.overrides[agentId] = {
    originalModel: existing?.originalModel || failedModel,
    currentModel: fallbackModel.modelName,
    currentModelLabel: fallbackModel.label,
    switchedAt: now(),
    switchedAtTs: ts(),
    reason,
  };

  // 更新 config 中的 defaultModel
  if (config.agents?.[agentId]) {
    config.agents[agentId].defaultModel = fallbackModel.modelName;
    writeJson(CONFIG_FILE, config);
  }

  state.stats.totalSwitches++;
  writeJson(STATE_FILE, state);

  addLog('switch', `Agent「${config.agents?.[agentId]?.label || agentId}」模型切换: ${failedModel} → ${fallbackModel.modelName}`, {
    agentId, from: failedModel, to: fallbackModel.modelName, reason,
  });

  return true;
}

/**
 * 自动恢复：模型恢复后，将 Agent 切回原始模型
 */
function recoverAgent(agentId) {
  const override = state.overrides?.[agentId];
  if (!override) return false;

  const originalModel = override.originalModel;
  if (!isModelHealthy(originalModel)) return false;

  // 切回
  if (config.agents?.[agentId]) {
    config.agents[agentId].defaultModel = originalModel;
    writeJson(CONFIG_FILE, config);
  }

  delete state.overrides[agentId];
  writeJson(STATE_FILE, state);

  addLog('recover', `Agent「${config.agents?.[agentId]?.label || agentId}」已恢复原始模型: ${originalModel}`, {
    agentId, model: originalModel,
  });

  return true;
}

// ─── 主检测循环 ───

async function runHealthCheck() {
  config = readJson(CONFIG_FILE, {}); // 每次重新读取
  const models = config.models || [];
  if (models.length === 0) return;

  const hm = config.healthMonitor || {};
  const failThreshold = hm.failThreshold || 3;
  const recoverThreshold = hm.recoverThreshold || 2;

  state.stats.totalChecks++;
  writeJson(STATE_FILE, state);

  console.log(`[${ts()}] 开始健康检测，共 ${models.length} 个模型...`);

  for (const model of models) {
    const result = await checkModel(model);

    if (!state.models[model.modelName]) {
      state.models[model.modelName] = { status: 'up', failCount: 0, recoverCount: 0, lastCheck: 0, checks: 0, fails: 0 };
    }

    const ms = state.models[model.modelName];
    ms.checks++;
    ms.lastCheck = now();
    ms.latency = result.latency;

    if (result.ok) {
      ms.failCount = 0;
      ms.recoverCount = (ms.recoverCount || 0) + 1;
      ms.lastUp = now();

      // 检查是否需要恢复
      if (ms.status === 'down' && ms.recoverCount >= recoverThreshold) {
        ms.status = 'up';
        ms.recoverCount = 0;
        addLog('up', `模型「${model.label}」已恢复正常`, { model: model.modelName, latency: result.latency });

        // 自动恢复受影响的 Agents
        if (hm.autoRecover !== false) {
          for (const [agentId, override] of Object.entries(state.overrides || {})) {
            if (override.originalModel === model.modelName) {
              recoverAgent(agentId);
            }
          }
        }
      }
    } else {
      ms.recoverCount = 0;
      ms.failCount = (ms.failCount || 0) + 1;
      ms.fails++;
      ms.lastFail = now();
      ms.lastError = result.error;

      if (ms.failCount >= failThreshold && ms.status === 'up') {
        ms.status = 'down';
        state.stats.totalFails++;
        addLog('down', `模型「${model.label}」不可用: ${result.error}`, {
          model: model.modelName, failCount: ms.failCount, error: result.error,
        });

        // 为使用该模型的 Agent 寻找替代
        for (const [agentId, agent] of Object.entries(config.agents || {})) {
          if (agent.defaultModel === model.modelName) {
            const fallback = findBestFallback(agentId, model.modelName);
            if (fallback) {
              switchAgent(agentId, model.modelName, fallback, `模型不可用 (${result.error?.slice(0,100)})`);
            } else {
              addLog('warn', `Agent「${agent.label}」无可用替代模型`, { agentId });
            }
          }
        }
      }
    }

    writeJson(STATE_FILE, state);
  }

  console.log(`[${ts()}] 健康检测完成`);
}

// ─── HTTP API（供 UI 查询）──────────

function startApiServer() {
  const PORT = parseInt(process.env.HEALTH_MONITOR_PORT) || 8091;

  const server = http.createServer((req, res) => {
    const cors = { 'Access-Control-Allow-Origin': '*', 'Access-Control-Allow-Methods': 'GET,POST', 'Access-Control-Allow-Headers': 'Content-Type' };

    if (req.method === 'OPTIONS') { res.writeHead(204, cors); res.end(); return; }

    if (req.url === '/api/health' && req.method === 'GET') {
      res.writeHead(200, { ...cors, 'Content-Type': 'application/json' });
      res.end(JSON.stringify(state));
    } else if (req.url === '/api/health/logs' && req.method === 'GET') {
      res.writeHead(200, { ...cors, 'Content-Type': 'application/json' });
      res.end(JSON.stringify(log.slice(0, 100)));
    } else if (req.url === '/api/health/check' && req.method === 'POST') {
      runHealthCheck().then(() => {
        res.writeHead(200, { ...cors, 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ ok: true, state }));
      });
    } else if (req.url === '/api/health/check-model' && req.method === 'POST') {
      let body = '';
      req.on('data', c => body += c);
      req.on('end', async () => {
        try {
          const { modelName } = JSON.parse(body);
          config = readJson(CONFIG_FILE, {});
          const model = (config.models || []).find(m => m.modelName === modelName);
          if (!model) {
            res.writeHead(404, { ...cors, 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ ok: false, error: '模型不存在' }));
            return;
          }
          const result = await checkModel(model);
          // Update state
          if (!state.models[modelName]) state.models[modelName] = { status: 'up', failCount: 0, recoverCount: 0, checks: 0, fails: 0 };
          const ms = state.models[modelName];
          ms.checks++;
          ms.lastCheck = now();
          ms.latency = result.latency;
          if (result.ok) {
            ms.status = 'up';
            ms.failCount = 0;
            ms.lastError = null;
            ms.lastUp = now();
          } else {
            ms.status = 'down';
            ms.failCount++;
            ms.fails++;
            ms.lastFail = now();
            ms.lastError = result.error;
            state.stats.totalFails++;
          }
          writeJson(STATE_FILE, state);
          res.writeHead(200, { ...cors, 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: result.ok, latency: result.latency, error: result.error || null, state }));
        } catch (e) {
          res.writeHead(400, { ...cors, 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok: false, error: e.message }));
        }
      });
    } else if (req.url === '/api/health/recover' && req.method === 'POST') {
      let body = '';
      req.on('data', c => body += c);
      req.on('end', () => {
        try {
          const { agentId } = JSON.parse(body);
          const ok = recoverAgent(agentId);
          res.writeHead(200, { ...cors, 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ ok }));
        } catch (e) {
          res.writeHead(400, { ...cors, 'Content-Type': 'application/json' });
          res.end(JSON.stringify({ error: e.message }));
        }
      });
    } else {
      res.writeHead(404, cors);
      res.end('Not Found');
    }
  });

  server.listen(PORT, '0.0.0.0', () => {
    console.log(`健康监控 API 运行在 http://0.0.0.0:${PORT}`);
  });
}

// ─── 启动 ───

const INTERVAL = parseInt(process.env.HEALTH_CHECK_INTERVAL) || (config.healthMonitor?.checkIntervalMs) || 120000;

startApiServer();

// 立即执行一次
runHealthCheck();

// 定时执行
setInterval(() => {
  runHealthCheck().catch(e => console.error('Health check error:', e));
}, INTERVAL);

console.log(`健康监控已启动，检测间隔: ${INTERVAL/1000}s`);
