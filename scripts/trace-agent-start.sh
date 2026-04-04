#!/usr/bin/env sh
set -eu

if [ $# -lt 4 ]; then
  echo "usage: $0 <agent-id> <model> <task-type> <summary> [trace-id]"
  exit 1
fi

AGENT_ID="$1"
MODEL="$2"
TASK_TYPE="$3"
SUMMARY="$4"
TRACE_ID="${5:-$(date +%s)-$AGENT_ID}"
WORKSPACE="${WORKSPACE:-/home/node/.openclaw/workspace}"
RUNTIME_DIR="$WORKSPACE/agent-team/runtime"
LOG_FILE="$RUNTIME_DIR/execution-log.jsonl"
mkdir -p "$RUNTIME_DIR"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

node -e '
  const fs = require("fs");
  const [file, time, traceId, agentId, model, taskType, summary] = process.argv.slice(1);
  const entry = { time, event: "start", traceId, agentId, model, taskType, summary };
  fs.appendFileSync(file, JSON.stringify(entry) + "\n");
' "$LOG_FILE" "$NOW_ISO" "$TRACE_ID" "$AGENT_ID" "$MODEL" "$TASK_TYPE" "$SUMMARY"

echo "$TRACE_ID"
