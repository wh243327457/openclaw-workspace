#!/usr/bin/env sh
set -eu

if [ $# -lt 3 ]; then
  echo "usage: $0 <trace-id> <status> <next-action> [notes]"
  exit 1
fi

TRACE_ID="$1"
STATUS="$2"
NEXT_ACTION="$3"
NOTES="${4:-}"
WORKSPACE="${WORKSPACE:-/home/node/.openclaw/workspace}"
RUNTIME_DIR="$WORKSPACE/agent-team/runtime"
LOG_FILE="$RUNTIME_DIR/execution-log.jsonl"
mkdir -p "$RUNTIME_DIR"
NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

node -e '
  const fs = require("fs");
  const [file, time, traceId, status, nextAction, notes] = process.argv.slice(1);
  const entry = { time, event: "finish", traceId, status, nextAction, notes };
  fs.appendFileSync(file, JSON.stringify(entry) + "\n");
' "$LOG_FILE" "$NOW_ISO" "$TRACE_ID" "$STATUS" "$NEXT_ACTION" "$NOTES"

echo "logged finish: $TRACE_ID"
