#!/usr/bin/env sh
set -eu

if [ $# -lt 2 ]; then
  echo "usage: $0 <role> <task-summary> [output-file]"
  exit 1
fi

ROLE="$1"
TASK="$2"
OUTFILE="${3:-/dev/stdout}"
TODAY="$(date +%F-%H%M)"

cat > "$OUTFILE" <<EOF
# Dispatch: $ROLE

- Date: $TODAY
- Task: $TASK
- Status: pending

## Context

<!-- fill in relevant context -->

## Inputs

<!-- list files, decisions, or constraints -->

## Allowed Actions

<!-- what this role may modify or produce -->

## Expected Output

<!-- what shape the result should take -->

## Escalate If

- sensitive information may be involved
- the change affects broad future behavior
- confidence is low
EOF

echo "Dispatch prepared: $OUTFILE"
