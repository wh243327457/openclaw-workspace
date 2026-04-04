#!/usr/bin/env sh
set -eu

if [ $# -lt 1 ]; then
  echo "usage: $0 <task-keyword> [role-hint]"
  exit 1
fi

KEYWORD="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
ROLE_HINT="${2:-}"
WORKSPACE="${WORKSPACE:-/home/node/.openclaw/workspace}"
CONFIG_FILE="$WORKSPACE/agent-team/config.json"
STATE_FILE="$WORKSPACE/agent-team/health-state.json"

node - <<'NODE' "$CONFIG_FILE" "$STATE_FILE" "$KEYWORD" "$ROLE_HINT"
const fs = require('fs');
const [configPath, statePath, keyword, roleHint] = process.argv.slice(2);
const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
const state = fs.existsSync(statePath) ? JSON.parse(fs.readFileSync(statePath, 'utf8')) : { models: {}, overrides: {} };

function routeKeyword(key) {
  switch (key) {
    case 'memory':
    case 'remember':
    case 'mem':
    case 'recall':
    case 'promote':
    case 'update-memory':
    case 'shared-memory':
      return { role: 'memory-operator', taskType: 'memory' };
    case 'skill':
    case 'create-skill':
    case 'skill-builder':
    case 'build-skill':
    case 'improve-skill':
      return { role: 'skill-builder', taskType: 'skills' };
    case 'project':
    case 'execute':
    case 'implement':
    case 'deploy':
    case 'multi-step':
    case 'plan':
      return { role: 'project-operator', taskType: 'execution' };
    case 'review':
    case 'check':
    case 'inspect':
    case 'validate':
    case 'verify':
    case 'audit':
    case 'merge':
      return { role: 'review-agent', taskType: 'review' };
    default:
      return { role: 'main-assistant', taskType: 'direct' };
  }
}

function isHealthy(modelName) {
  const m = state.models?.[modelName];
  if (!m) return true;
  return m.status !== 'down';
}

function latency(modelName) {
  const m = state.models?.[modelName];
  return typeof m?.latency === 'number' ? m.latency : 999999;
}

const routed = routeKeyword(keyword);
const agentId = roleHint || routed.role;
const agent = config.agents?.[agentId];
if (!agent) {
  console.log(JSON.stringify({ agentId: 'main-assistant', model: config.agents?.['main-assistant']?.defaultModel || '', reason: 'unknown agent, fallback to main-assistant', fallbackUsed: false, taskType: routed.taskType }, null, 2));
  process.exit(0);
}

const override = state.overrides?.[agentId];
const currentDefault = agent.defaultModel || '';
const candidates = [currentDefault, ...(agent.fallbackModels || [])].filter(Boolean);

let selected = '';
let fallbackUsed = false;
let reason = '';

if (override && override.currentModel && candidates.includes(override.currentModel) && isHealthy(override.currentModel)) {
  selected = override.currentModel;
  fallbackUsed = override.currentModel !== currentDefault;
  reason = `health override active for ${agentId}`;
} else if (currentDefault && isHealthy(currentDefault)) {
  selected = currentDefault;
  reason = 'role default model healthy';
} else {
  const healthyFallbacks = candidates.filter((m, idx) => idx > 0 && isHealthy(m));
  if (healthyFallbacks.length > 0) {
    healthyFallbacks.sort((a, b) => latency(a) - latency(b));
    selected = healthyFallbacks[0];
    fallbackUsed = true;
    reason = 'default model unhealthy, fallback selected by health/latency';
  } else {
    selected = currentDefault || candidates[0] || '';
    fallbackUsed = true;
    reason = 'no healthy fallback found, using best available configured model';
  }
}

console.log(JSON.stringify({
  agentId,
  model: selected,
  reason,
  fallbackUsed,
  taskType: routed.taskType,
  defaultModel: currentDefault,
  overrideModel: override?.currentModel || null
}, null, 2));
NODE
