#!/usr/bin/env sh
set -eu

WORKSPACE="${WORKSPACE:-/home/node/.openclaw/workspace}"
RUNTIME_DIR="$WORKSPACE/agent-team/runtime"
LOG_FILE="$RUNTIME_DIR/dispatch-log.jsonl"

if [ ! -f "$LOG_FILE" ]; then
  echo "No dispatch log yet: $LOG_FILE"
  exit 0
fi

node - <<'NODE' "$LOG_FILE"
const fs = require('fs');
const path = process.argv[2];
const lines = fs.readFileSync(path, 'utf8').trim().split('\n').filter(Boolean);
const entries = lines.map((line) => JSON.parse(line));
const byRole = new Map();
const byKeyword = new Map();
for (const entry of entries) {
  byRole.set(entry.role, (byRole.get(entry.role) || 0) + 1);
  byKeyword.set(entry.keyword, (byKeyword.get(entry.keyword) || 0) + 1);
}
console.log('Dispatch count:', entries.length);
console.log('');
console.log('By role:');
for (const [role, count] of [...byRole.entries()].sort((a,b)=>b[1]-a[1])) {
  console.log(`- ${role}: ${count}`);
}
console.log('');
console.log('By keyword:');
for (const [keyword, count] of [...byKeyword.entries()].sort((a,b)=>b[1]-a[1])) {
  console.log(`- ${keyword}: ${count}`);
}
console.log('');
console.log('Last 5:');
for (const entry of entries.slice(-5)) {
  console.log(`- ${entry.time} | ${entry.role} | ${entry.summary || entry.keyword}`);
}
NODE
