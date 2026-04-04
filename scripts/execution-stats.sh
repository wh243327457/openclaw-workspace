#!/usr/bin/env sh
set -eu

WORKSPACE="${WORKSPACE:-/home/node/.openclaw/workspace}"
RUNTIME_DIR="$WORKSPACE/agent-team/runtime"
DISPATCH_LOG="$RUNTIME_DIR/dispatch-log.jsonl"
EXEC_LOG="$RUNTIME_DIR/execution-log.jsonl"

node - <<'NODE' "$DISPATCH_LOG" "$EXEC_LOG"
const fs = require('fs');
const [dispatchPath, execPath] = process.argv.slice(2);
const readJsonl = (p) => {
  if (!fs.existsSync(p)) return [];
  return fs.readFileSync(p, 'utf8').trim().split('\n').filter(Boolean).map((line) => JSON.parse(line));
};
const dispatch = readJsonl(dispatchPath);
const execution = readJsonl(execPath);
const starts = execution.filter((e) => e.event === 'start');
const finishes = execution.filter((e) => e.event === 'finish');
const byAgent = new Map();
for (const item of starts) byAgent.set(item.agentId, (byAgent.get(item.agentId) || 0) + 1);
const finishMap = new Map(finishes.map((e) => [e.traceId, e]));
let completed = 0;
let pending = 0;
for (const item of starts) {
  if (finishMap.has(item.traceId)) completed += 1;
  else pending += 1;
}
console.log('Dispatch count:', dispatch.length);
console.log('Execution starts:', starts.length);
console.log('Execution completed:', completed);
console.log('Execution pending:', pending);
console.log('');
console.log('Execution by agent:');
for (const [agent, count] of [...byAgent.entries()].sort((a,b)=>b[1]-a[1])) {
  console.log(`- ${agent}: ${count}`);
}
console.log('');
console.log('Recent execution events:');
for (const entry of execution.slice(-8)) {
  if (entry.event === 'start') {
    console.log(`- ${entry.time} | start | ${entry.agentId} | ${entry.model} | ${entry.summary}`);
  } else {
    console.log(`- ${entry.time} | finish | ${entry.traceId} | ${entry.status} | ${entry.nextAction}`);
  }
}
NODE
