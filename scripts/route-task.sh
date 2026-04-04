#!/usr/bin/env sh
set -eu

if [ $# -lt 1 ]; then
  echo "usage: $0 <task-keyword>"
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
  echo "  $0 create-skill"
  echo "  $0 review"
  exit 0
fi

KEYWORD="$(echo "$1" | tr '[:upper:]' '[:lower:]')"

case "$KEYWORD" in
  memory|remember|mem|recall|promote|update-memory|shared-memory)
    ROLE="memory-operator"
    ;;
  skill|create-skill|skill-builder|build-skill|improve-skill)
    ROLE="skill-builder"
    ;;
  project|execute|implement|deploy|multi-step|plan)
    ROLE="project-operator"
    ;;
  review|check|inspect|validate|verify|audit|merge)
    ROLE="review-agent"
    ;;
  direct|simple|answer|explain|quick)
    ROLE="main-assistant"
    ;;
  *)
    echo "Unknown keyword: $KEYWORD"
    echo "Suggestion: use direct for simple tasks"
    ROLE="main-assistant"
    ;;
esac

echo "Route: $KEYWORD -> $ROLE"
echo
echo "Dispatch command:"
echo "  sh scripts/prepare-dispatch.sh $ROLE \"<task-summary>\""
