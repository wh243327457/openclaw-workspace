#!/bin/sh
# tenant 卡死 / 状态不一致时的保守修复入口
# 用法:
#   sh scripts/repair-tenant.sh <tenantId>
#   sh scripts/repair-tenant.sh <tenantId> --force

set -e

WORKSPACE="${WORKSPACE:-/home/node/.openclaw/workspace}"
REGISTRY="${REGISTRY:-$WORKSPACE/tenants/registry.json}"
CONFIG_FILE="${CONFIG_FILE:-$HOME/.openclaw/openclaw.json}"
ALLOW_FROM_FILE="${ALLOW_FROM_FILE:-$HOME/.openclaw/credentials/openclaw-weixin-allowFrom.json}"
WX_ACCOUNTS_FILE="${WX_ACCOUNTS_FILE:-$HOME/.openclaw/openclaw-weixin/accounts.json}"
OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
TENANT_ID=""
FORCE="false"
RELOAD_NEEDED="false"
CHANGED="false"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --force)
      FORCE="true"
      shift
      ;;
    *)
      if [ -z "$TENANT_ID" ]; then
        TENANT_ID="$1"
        shift
      else
        echo "用法: sh scripts/repair-tenant.sh <tenantId> [--force]"
        exit 1
      fi
      ;;
  esac
done

if [ -z "$TENANT_ID" ]; then
  echo "用法: sh scripts/repair-tenant.sh <tenantId> [--force]"
  echo "例: sh scripts/repair-tenant.sh friend-001 --force"
  exit 1
fi

PENDING_FILE="$WORKSPACE/tenants/${TENANT_ID}-pending.json"
WATCH_PID_FILE="$WORKSPACE/tenants/${TENANT_ID}-watch.pid"
LOGIN_LOG="$WORKSPACE/tenants/${TENANT_ID}-login.log"

pid_is_alive() {
  PID="$1"
  [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null
}

json_quote() {
  node -e 'console.log(JSON.stringify(process.argv[1] || ""))' "$1"
}

update_registry_tenant() {
  node -e '
    const fs = require("fs");
    const [registryPath, tenantId, patchJson] = process.argv.slice(1);
    const reg = JSON.parse(fs.readFileSync(registryPath, "utf8"));
    if (!reg.tenants?.[tenantId]) process.exit(1);
    const patch = JSON.parse(patchJson);
    reg.tenants[tenantId] = { ...reg.tenants[tenantId], ...patch };
    fs.writeFileSync(registryPath, JSON.stringify(reg, null, 2));
  ' "$REGISTRY" "$TENANT_ID" "$1"
  CHANGED="true"
}

archive_pending() {
  REASON="$1"
  if [ ! -f "$PENDING_FILE" ]; then
    return 0
  fi
  TS="$(date +%s)"
  node -e '
    const fs = require("fs");
    const [filePath, reason] = process.argv.slice(1);
    const current = JSON.parse(fs.readFileSync(filePath, "utf8"));
    current.status = reason;
    current.archivedAt = new Date().toISOString();
    fs.writeFileSync(filePath, JSON.stringify(current, null, 2));
  ' "$PENDING_FILE" "$REASON" >/dev/null 2>&1 || true
  mv "$PENDING_FILE" "$WORKSPACE/tenants/${TENANT_ID}-pending-${REASON}-repair-${TS}.json"
  CHANGED="true"
}

binding_account() {
  node -e '
    const fs = require("fs");
    const cfg = fs.existsSync(process.argv[1]) ? JSON.parse(fs.readFileSync(process.argv[1], "utf8")) : {};
    const tenantId = process.argv[2];
    const binding = (cfg.bindings || []).find(b => b.agentId === tenantId);
    console.log(binding?.match?.accountId || "");
  ' "$CONFIG_FILE" "$TENANT_ID" 2>/dev/null || true
}

registry_field() {
  node -e '
    const fs = require("fs");
    const reg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    const tenant = reg.tenants?.[process.argv[2]];
    if (!tenant) process.exit(1);
    const value = tenant[process.argv[3]];
    if (typeof value === "object") console.log(JSON.stringify(value));
    else console.log(value ?? "");
  ' "$REGISTRY" "$TENANT_ID" "$1"
}

if ! node -e '
  const fs = require("fs");
  const reg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (!reg.tenants?.[process.argv[2]]) process.exit(1);
' "$REGISTRY" "$TENANT_ID" 2>/dev/null; then
  echo "❌ Tenant 不存在: $TENANT_ID"
  exit 1
fi

echo "🔧 开始修复 $TENANT_ID..."

REG_ACCOUNT_ID="$(registry_field accountId)"
REG_PEER_ID="$(registry_field peerId)"
REG_STATUS="$(registry_field status)"
REG_BOUND="$(registry_field bound)"
ACTUAL_BINDING="$(binding_account)"

if [ -f "$PENDING_FILE" ]; then
  PENDING_LOGIN_PID=$(node -e '
    const fs = require("fs");
    const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    console.log(p.loginPid || "");
  ' "$PENDING_FILE" 2>/dev/null || true)
  PENDING_WATCH_PID=$(node -e '
    const fs = require("fs");
    const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    console.log(p.watchPid || "");
  ' "$PENDING_FILE" 2>/dev/null || true)
  PENDING_STATUS=$(node -e '
    const fs = require("fs");
    const p = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    console.log(p.status || "unknown");
  ' "$PENDING_FILE" 2>/dev/null || echo unknown)

  if pid_is_alive "$PENDING_LOGIN_PID" || pid_is_alive "$PENDING_WATCH_PID"; then
    if [ "$FORCE" = "true" ]; then
      echo "⚠️  检测到活跃中的 login/watch 进程，按 --force 终止并回收 pending"
      pid_is_alive "$PENDING_LOGIN_PID" && kill "$PENDING_LOGIN_PID" 2>/dev/null || true
      pid_is_alive "$PENDING_WATCH_PID" && kill "$PENDING_WATCH_PID" 2>/dev/null || true
      rm -f "$WATCH_PID_FILE"
      archive_pending "forced-stale"
      update_registry_tenant '{"status":"awaiting_scan"}' >/dev/null 2>&1 || true
    else
      echo "⚠️  当前仍有活跃中的二维码流程（pending status: $PENDING_STATUS）"
      echo "如确认卡住，可执行：sh scripts/repair-tenant.sh $TENANT_ID --force"
      exit 1
    fi
  else
    echo "ℹ️  检测到陈旧 pending，自动归档"
    rm -f "$WATCH_PID_FILE"
    archive_pending "stale"
    if [ -z "$ACTUAL_BINDING" ] && [ -z "$REG_ACCOUNT_ID" ]; then
      update_registry_tenant '{"status":"awaiting_scan"}' >/dev/null 2>&1 || true
    fi
  fi
fi

if [ -f "$WATCH_PID_FILE" ]; then
  WATCH_PID=$(cat "$WATCH_PID_FILE" 2>/dev/null || true)
  if ! pid_is_alive "$WATCH_PID"; then
    echo "ℹ️  清理失效的 watch pid: ${WATCH_PID:-unknown}"
    rm -f "$WATCH_PID_FILE"
    CHANGED="true"
  fi
fi

if [ -n "$REG_ACCOUNT_ID" ] && [ -n "$ACTUAL_BINDING" ] && [ "$REG_ACCOUNT_ID" != "$ACTUAL_BINDING" ]; then
  echo "❌ registry/account 与实际 binding 不一致: registry=$REG_ACCOUNT_ID, actual=$ACTUAL_BINDING"
  update_registry_tenant "{\"status\":\"binding-mismatch\"}" >/dev/null 2>&1 || true
  exit 1
fi

if [ -z "$REG_ACCOUNT_ID" ] && [ -n "$ACTUAL_BINDING" ]; then
  echo "ℹ️  registry 缺失 accountId，已按实际 binding 回填: $ACTUAL_BINDING"
  update_registry_tenant "{\"accountId\":$(json_quote "$ACTUAL_BINDING"),\"bound\":true,\"status\":\"bound\"}" >/dev/null 2>&1 || true
  REG_ACCOUNT_ID="$ACTUAL_BINDING"
  REG_BOUND="true"
fi

if [ -n "$REG_ACCOUNT_ID" ] && [ -z "$ACTUAL_BINDING" ]; then
  if node -e '
    const fs = require("fs");
    const list = fs.existsSync(process.argv[1]) ? JSON.parse(fs.readFileSync(process.argv[1], "utf8")) : [];
    if (!list.includes(process.argv[2])) process.exit(1);
  ' "$WX_ACCOUNTS_FILE" "$REG_ACCOUNT_ID" 2>/dev/null; then
    echo "ℹ️  检测到 registry 有 accountId 但 binding 丢失，尝试自动恢复"
    $OPENCLAW_BIN agents bind --agent "$TENANT_ID" --bind "openclaw-weixin:$REG_ACCOUNT_ID" >/dev/null
    RELOAD_NEEDED="true"
    CHANGED="true"
    ACTUAL_BINDING="$REG_ACCOUNT_ID"
    update_registry_tenant "{\"bound\":true,\"status\":\"bound\"}" >/dev/null 2>&1 || true
  else
    echo "⚠️  registry 记录了 accountId=$REG_ACCOUNT_ID，但 accounts.json 中不存在，无法自动恢复 binding"
    update_registry_tenant "{\"status\":\"binding-error\"}" >/dev/null 2>&1 || true
  fi
fi

if [ -n "$REG_PEER_ID" ]; then
  if [ ! -f "$ALLOW_FROM_FILE" ]; then
    mkdir -p "$(dirname "$ALLOW_FROM_FILE")"
    echo '[]' > "$ALLOW_FROM_FILE"
  fi

  if ! node -e '
    const fs = require("fs");
    const file = process.argv[1];
    const peerId = process.argv[2];
    const list = JSON.parse(fs.readFileSync(file, "utf8"));
    if (!list.includes(peerId)) process.exit(1);
  ' "$ALLOW_FROM_FILE" "$REG_PEER_ID" 2>/dev/null; then
    echo "ℹ️  allowlist 缺失 peerId，已自动补入: $REG_PEER_ID"
    node -e '
      const fs = require("fs");
      const [file, peerId] = process.argv.slice(1);
      const list = JSON.parse(fs.readFileSync(file, "utf8"));
      list.push(peerId);
      fs.writeFileSync(file, JSON.stringify([...new Set(list)], null, 2));
    ' "$ALLOW_FROM_FILE" "$REG_PEER_ID"
    RELOAD_NEEDED="true"
    CHANGED="true"
  fi
fi

FINAL_STATUS="$REG_STATUS"
if [ -n "$REG_ACCOUNT_ID" ] || [ -n "$ACTUAL_BINDING" ]; then
  if [ -n "$REG_PEER_ID" ]; then
    if node -e '
      const fs = require("fs");
      const file = process.argv[1];
      const peerId = process.argv[2];
      const list = fs.existsSync(file) ? JSON.parse(fs.readFileSync(file, "utf8")) : [];
      if (!list.includes(peerId)) process.exit(1);
    ' "$ALLOW_FROM_FILE" "$REG_PEER_ID" 2>/dev/null; then
      FINAL_STATUS="active"
      update_registry_tenant "{\"status\":\"active\",\"allowlisted\":true,\"bound\":true}" >/dev/null 2>&1 || true
    else
      FINAL_STATUS="bound-awaiting-first-message"
      update_registry_tenant "{\"status\":\"bound-awaiting-first-message\",\"allowlisted\":false,\"bound\":true}" >/dev/null 2>&1 || true
    fi
  else
    FINAL_STATUS="bound-awaiting-first-message"
    update_registry_tenant "{\"status\":\"bound-awaiting-first-message\",\"bound\":true}" >/dev/null 2>&1 || true
  fi
else
  FINAL_STATUS="awaiting_scan"
  update_registry_tenant "{\"status\":\"awaiting_scan\",\"bound\":false,\"allowlisted\":false}" >/dev/null 2>&1 || true
fi

if [ "$RELOAD_NEEDED" = "true" ]; then
  echo "🔄 检测到 binding/allowlist 变更，触发 gateway 热重载..."
  sh "$WORKSPACE/scripts/gateway-reload.sh" >/dev/null || true
fi

echo "✅ 修复完成"
echo "  - tenant: $TENANT_ID"
echo "  - final status: $FINAL_STATUS"
echo "  - registry accountId: ${REG_ACCOUNT_ID:-未绑定}"
echo "  - binding accountId: $(binding_account)"
echo "  - peerId: ${REG_PEER_ID:-未知}"

if [ "$CHANGED" = "true" ]; then
  echo "  - 结果: 已做修复"
else
  echo "  - 结果: 无需修改"
fi
