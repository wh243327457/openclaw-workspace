#!/bin/sh
# tenant 一致性巡检入口
# 用法:
#   sh scripts/check-tenants.sh
#   sh scripts/check-tenants.sh <tenantId>
#   sh scripts/check-tenants.sh repair <tenantId>

set -e

WORKSPACE="/home/node/.openclaw/workspace"
ACTION="${1:-check}"
TARGET="${2:-}"

case "$ACTION" in
  check)
    if [ -n "$TARGET" ]; then
      sh "$WORKSPACE/scripts/healthcheck-tenant.sh" "$TARGET"
    else
      sh "$WORKSPACE/scripts/healthcheck-tenant.sh"
    fi
    ;;
  repair)
    if [ -z "$TARGET" ]; then
      echo "用法: sh scripts/check-tenants.sh repair <tenantId>"
      exit 1
    fi
    sh "$WORKSPACE/scripts/repair-tenant.sh" "$TARGET"
    ;;
  *)
    # 兼容旧用法：第一个参数直接就是 tenantId
    sh "$WORKSPACE/scripts/healthcheck-tenant.sh" "$ACTION"
    ;;
 esac
