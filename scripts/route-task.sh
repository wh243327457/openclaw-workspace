#!/usr/bin/env sh
set -eu

if [ $# -lt 1 ]; then
  echo "usage: $0 <task-keyword> [task-summary]"
  echo
  echo "Keywords:"
  echo "  memory          -> memory-operator"
  echo "  remember        -> memory-operator"
  echo "  skill           -> skill-builder"
  echo "  create-skill    -> skill-builder"
  echo "  project         -> project-operator"
  echo "  execute         -> project-operator"
  echo "  review          -> review-agent"
  echo "  check           -> review-agent"
  echo "  direct          -> main-assistant (solve directly)"
  echo
  echo "Examples:"
  echo "  $0 remember"
  echo "  $0 create-skill \"整理一个技能目录\""
  echo "  $0 project \"实现租户修复脚本\""
  exit 0
fi

KEYWORD="$(echo "$1" | tr '[:upper:]' '[:lower:]')"
TASK_SUMMARY="${2:-}"
WORKSPACE="${WORKSPACE:-/home/node/.openclaw/workspace}"
RUNTIME_DIR="$WORKSPACE/agent-team/runtime"
LOG_FILE="$RUNTIME_DIR/dispatch-log.jsonl"
mkdir -p "$RUNTIME_DIR"

case "$KEYWORD" in
  memory|remember|mem|recall|promote|update-memory|shared-memory)
    ROLE="memory-operator"
    TASK_TYPE="memory"
    ;;
  skill|create-skill|skill-builder|build-skill|improve-skill)
    ROLE="skill-builder"
    TASK_TYPE="skills"
    ;;
  project|execute|implement|deploy|multi-step|plan)
    ROLE="project-operator"
    TASK_TYPE="execution"
    ;;
  review|check|inspect|validate|verify|audit|merge)
    ROLE="review-agent"
    TASK_TYPE="review"
    ;;
  direct|simple|answer|explain|quick)
    ROLE="main-assistant"
    TASK_TYPE="direct"
    ;;
  *)
    echo "Unknown keyword: $KEYWORD"
    echo "Suggestion: use direct for simple tasks"
    ROLE="main-assistant"
    TASK_TYPE="direct"
    ;;
esac

NOW_ISO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
if [ -n "$TASK_SUMMARY" ]; then
  node -e '
    const fs = require("fs");
    const [file, time, keyword, role, taskType, summary] = process.argv.slice(1);
    const entry = { time, keyword, role, taskType, summary };
    fs.appendFileSync(file, JSON.stringify(entry) + "\n");
  ' "$LOG_FILE" "$NOW_ISO" "$KEYWORD" "$ROLE" "$TASK_TYPE" "$TASK_SUMMARY"
fi

echo "Route: $KEYWORD -> $ROLE"
[ -n "$TASK_SUMMARY" ] && echo "Task: $TASK_SUMMARY"
echo
echo "Dispatch command:"
echo "  sh scripts/prepare-dispatch.sh $ROLE \"<task-summary>\""
[ -n "$TASK_SUMMARY" ] && echo "  sh scripts/prepare-dispatch.sh $ROLE \"$TASK_SUMMARY\""
echo
echo "Dispatch log: $LOG_FILE"
