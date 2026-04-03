#!/bin/sh
# tenant 一致性巡检 / 健康检查
# 用法:
#   sh scripts/healthcheck-tenant.sh
#   sh scripts/healthcheck-tenant.sh <tenantId>

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
CONFIG_FILE="$HOME/.openclaw/openclaw.json"
ALLOW_FROM_FILE="$HOME/.openclaw/credentials/openclaw-weixin-allowFrom.json"
AGENTS_DIR="$HOME/.openclaw/agents"
ACCOUNTS_FILE="$HOME/.openclaw/openclaw-weixin/accounts.json"

if [ -t 1 ]; then
  GREEN='\033[0;32m'
  YELLOW='\033[1;33m'
  RED='\033[0;31m'
  CYAN='\033[0;36m'
  NC='\033[0m'
else
  GREEN=''
  YELLOW=''
  RED=''
  CYAN=''
  NC=''
fi

ok()   { printf '  %s✅ %s%s\n' "$GREEN" "$1" "$NC"; }
warn() { printf '  %s⚠️  %s%s\n' "$YELLOW" "$1" "$NC"; }
fail() { printf '  %s❌ %s%s\n' "$RED" "$1" "$NC"; }
info() { printf '  %sℹ️  %s%s\n' "$CYAN" "$1" "$NC"; }

json_get() {
  node -e 'const obj=JSON.parse(process.argv[1]); const key=process.argv[2]; const v=obj?.[key]; if (typeof v === "object") console.log(JSON.stringify(v)); else console.log(v ?? "");' "$1" "$2"
}

check_tenant() {
  TID="$1"
  ISSUES=0
  WARNINGS=0

  printf '\n%s━━━ %s ━━━%s\n' "$CYAN" "$TID" "$NC"

  TENANT_JSON=$(node -e '
    const fs = require("fs");
    const reg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const t = reg.tenants?.[process.argv[2]];
    if (!t) process.exit(1);
    console.log(JSON.stringify(t));
  ' "$REGISTRY" "$TID" 2>/dev/null) || {
    fail "注册表中不存在 tenant"
    return 1
  }

  DISPLAY_NAME=$(json_get "$TENANT_JSON" displayName)
  STATUS=$(json_get "$TENANT_JSON" status)
  ACCOUNT_ID=$(json_get "$TENANT_JSON" accountId)
  PEER_ID=$(json_get "$TENANT_JSON" peerId)
  WORKSPACE_PATH=$(json_get "$TENANT_JSON" workspace)
  BOUND=$(json_get "$TENANT_JSON" bound)

  info "显示名: ${DISPLAY_NAME:-未知}"
  info "状态: ${STATUS:-未标记}"
  info "账号ID: ${ACCOUNT_ID:-未绑定}"
  info "Peer ID: ${PEER_ID:-未知}"

  if [ -d "$WORKSPACE_PATH" ]; then
    ok "Workspace 存在: $WORKSPACE_PATH"
  else
    fail "Workspace 不存在: $WORKSPACE_PATH"
    ISSUES=$((ISSUES+1))
  fi

  if [ -d "$AGENTS_DIR/$TID" ]; then
    ok "Agent 目录存在"
  else
    fail "Agent 目录不存在"
    ISSUES=$((ISSUES+1))
  fi

  BINDING_ACCOUNT=$(node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const tenantId = process.argv[2];
    const cfg = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : {};
    const bindings = cfg.bindings || [];
    const match = bindings.find(b => b.agentId === tenantId);
    console.log(match?.match?.accountId || "");
  ' "$CONFIG_FILE" "$TID" 2>/dev/null || true)

  if [ -n "$ACCOUNT_ID" ]; then
    if [ "$BINDING_ACCOUNT" = "$ACCOUNT_ID" ]; then
      ok "Binding 一致: $ACCOUNT_ID → $TID"
    else
      fail "Binding 不一致: registry=$ACCOUNT_ID, actual=${BINDING_ACCOUNT:-无}"
      ISSUES=$((ISSUES+1))
    fi
  else
    if [ -n "$BINDING_ACCOUNT" ]; then
      warn "存在 binding 但 registry 未记录 accountId: $BINDING_ACCOUNT"
      WARNINGS=$((WARNINGS+1))
    else
      info "当前无 binding"
    fi
  fi

  if [ -n "$ACCOUNT_ID" ]; then
    if node -e '
      const fs = require("fs");
      const file = process.argv[1];
      const accountId = process.argv[2];
      const list = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : [];
      if (!list.includes(accountId)) process.exit(1);
    ' "$ACCOUNTS_FILE" "$ACCOUNT_ID" 2>/dev/null; then
      ok "accounts.json 中存在 accountId"
    else
      fail "accounts.json 中缺失 accountId: $ACCOUNT_ID"
      ISSUES=$((ISSUES+1))
    fi
  fi

  if [ -n "$PEER_ID" ]; then
    if node -e '
      const fs = require("fs");
      const file = process.argv[1];
      const peerId = process.argv[2];
      const list = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : [];
      if (!list.includes(peerId)) process.exit(1);
    ' "$ALLOW_FROM_FILE" "$PEER_ID" 2>/dev/null; then
      ok "白名单包含 peerId"
    else
      if [ "$STATUS" = "active" ]; then
        fail "状态为 active，但白名单缺失 peerId"
        ISSUES=$((ISSUES+1))
      else
        warn "尚未进入白名单（可能还未首条消息）"
        WARNINGS=$((WARNINGS+1))
      fi
    fi
  else
    warn "未记录 peerId"
    WARNINGS=$((WARNINGS+1))
  fi

  PENDING_FILE="$WORKSPACE/tenants/${TID}-pending.json"
  if [ -f "$PENDING_FILE" ]; then
    PENDING_STATUS=$(node -e '
      const fs = require("fs");
      const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      console.log(p.status || "unknown");
    ' "$PENDING_FILE" 2>/dev/null || echo unknown)
    warn "存在 pending 文件，状态: $PENDING_STATUS"
    WARNINGS=$((WARNINGS+1))
  fi

  if [ "$BOUND" = "true" ] && [ -z "$ACCOUNT_ID" ]; then
    fail "registry 标记为 bound=true，但没有 accountId"
    ISSUES=$((ISSUES+1))
  fi

  printf '\n'
  if [ "$ISSUES" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
    printf '  %s状态: HEALTHY ✓%s\n' "$GREEN" "$NC"
  elif [ "$ISSUES" -eq 0 ]; then
    printf '  %s状态: WARN (%s warnings)%s\n' "$YELLOW" "$WARNINGS" "$NC"
  else
    printf '  %s状态: FAIL (%s issues, %s warnings)%s\n' "$RED" "$ISSUES" "$WARNINGS" "$NC"
  fi

  [ "$ISSUES" -eq 0 ]
}

printf '%s=== Tenant 一致性巡检 ===%s\n' "$CYAN" "$NC"
TENANT_ID="${1:-}"

if [ -n "$TENANT_ID" ]; then
  check_tenant "$TENANT_ID"
  exit $?
fi

TENANTS=$(node -e '
  const fs = require("fs");
  const reg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  Object.keys(reg.tenants || {}).forEach(k => console.log(k));
' "$REGISTRY" 2>/dev/null)

if [ -z "$TENANTS" ]; then
  info "没有配置任何 tenant"
  exit 0
fi

TOTAL=0
FAIL_COUNT=0
for TID in $TENANTS; do
  TOTAL=$((TOTAL+1))
  if ! check_tenant "$TID"; then
    FAIL_COUNT=$((FAIL_COUNT+1))
  fi
done

printf '\n%s=== 总览 ===%s\n' "$CYAN" "$NC"
printf '  总计: %s\n' "$TOTAL"
printf '  异常: %s\n' "$FAIL_COUNT"
[ "$FAIL_COUNT" -eq 0 ] && printf '  %s全部通过%s\n' "$GREEN" "$NC"
