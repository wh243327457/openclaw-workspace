#!/usr/bin/env sh
set -eu

TODAY="$(date +%F-%H%M)"
CHECKPOINT_DIR="/home/node/.openclaw/workspace/agent-team/checkpoints"
TEMPLATE="$CHECKPOINT_DIR/template.md"
CHECKPOINT_FILE="$CHECKPOINT_DIR/$TODAY-checkpoint.md"

if [ ! -d "$CHECKPOINT_DIR" ]; then
  mkdir -p "$CHECKPOINT_DIR"
fi

if [ -f "$TEMPLATE" ]; then
  cp "$TEMPLATE" "$CHECKPOINT_FILE"
  echo "Checkpoint created: $CHECKPOINT_FILE"
  echo "Fill in the details before saving."
else
  cat > "$CHECKPOINT_FILE" <<EOF
# Checkpoint

- Date: $TODAY
- Trigger: model switch / pause / handoff
- Status: draft

## Current Task

<!-- what is being worked on -->

## Completed

<!-- completed work -->

## Open Items

<!-- remaining work -->

## Risks

<!-- important caveats -->

## Resume Hint

<!-- how to continue quickly -->
EOF
  echo "Checkpoint created from built-in template: $CHECKPOINT_FILE"
fi
