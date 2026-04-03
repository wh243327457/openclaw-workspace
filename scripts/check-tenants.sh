#!/bin/sh
# tenant 一致性巡检入口
# 用法:
#   sh scripts/check-tenants.sh
#   sh scripts/check-tenants.sh <tenantId>

set -e

WORKSPACE="/home/node/.openclaw/workspace"
TARGET="${1:-}"

if [ -n "$TARGET" ]; then
  sh "$WORKSPACE/scripts/healthcheck-tenant.sh" "$TARGET"
else
  sh "$WORKSPACE/scripts/healthcheck-tenant.sh"
fi
