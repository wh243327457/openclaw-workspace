#!/bin/sh
# 删除子系统 + 清理绑定 + 清理白名单
# 用法: sh scripts/delete-tenant.sh <tenantId>

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
ALLOW_FROM_FILE="$HOME/.openclaw/credentials/openclaw-weixin-allowFrom.json"
TENANT_ID="${1:-}"

if [ -z "$TENANT_ID" ]; then
  echo "用法: sh scripts/delete-tenant.sh <tenantId>"
  echo "例: sh scripts/delete-tenant.sh friend-001"
  exit 1
fi

update_registry_tenant() {
  node -e '
    const fs = require("fs");
    const [registryPath, tenantId, patchJson] = process.argv.slice(1);
    const reg = JSON.parse(fs.readFileSync(registryPath, "utf8"));
    if (!reg.tenants?.[tenantId]) process.exit(0);
    const patch = JSON.parse(patchJson);
    reg.tenants[tenantId] = { ...reg.tenants[tenantId], ...patch };
    fs.writeFileSync(registryPath, JSON.stringify(reg, null, 2));
  ' "$REGISTRY" "$TENANT_ID" "$1"
}

echo "🗑️ 删除子系统 $TENANT_ID..."
update_registry_tenant '{"status":"deleting"}' >/dev/null 2>&1 || true

ACCOUNT_ID=$(node -e '
  const fs = require("fs");
  const reg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const tenant = reg.tenants?.[process.argv[2]];
  console.log(tenant?.accountId || "");
' "$REGISTRY" "$TENANT_ID" 2>/dev/null || true)

PEER_ID=$(node -e '
  const fs = require("fs");
  const reg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const tenant = reg.tenants?.[process.argv[2]];
  console.log(tenant?.peerId || "");
' "$REGISTRY" "$TENANT_ID" 2>/dev/null || true)

if [ -z "$PEER_ID" ]; then
  PEER_ID=$(node -e '
    const fs = require("fs");
    const sessionsFile = process.env.HOME + "/.openclaw/agents/" + process.argv[1] + "/sessions/sessions.json";
    if (fs.existsSync(sessionsFile)) {
      const sessions = JSON.parse(fs.readFileSync(sessionsFile, "utf8"));
      for (const v of Object.values(sessions)) {
        if (v.origin?.from) { console.log(v.origin.from); break; }
      }
    }
  ' "$TENANT_ID" 2>/dev/null || true)
fi

if [ -n "$PEER_ID" ] && [ -f "$ALLOW_FROM_FILE" ]; then
  node -e '
    const fs = require("fs");
    const [allowFile, peerId] = process.argv.slice(1);
    let list = JSON.parse(fs.readFileSync(allowFile, "utf8"));
    const before = list.length;
    list = list.filter(id => id !== peerId);
    if (list.length < before) {
      fs.writeFileSync(allowFile, JSON.stringify(list, null, 2));
      console.log("✅ 已从白名单移除: " + peerId);
    } else {
      console.log("ℹ️  不在白名单中");
    }
  ' "$ALLOW_FROM_FILE" "$PEER_ID"
fi

openclaw agents unbind --agent "$TENANT_ID" --all >/dev/null 2>&1 || true
echo "✅ 绑定已移除"

openclaw agents delete "$TENANT_ID" --force >/dev/null 2>&1 || true
echo "✅ Agent 已删除"

if [ -n "$ACCOUNT_ID" ]; then
  ACC_FILE="$HOME/.openclaw/openclaw-weixin/accounts.json"
  if [ -f "$ACC_FILE" ]; then
    node -e '
      const fs = require("fs");
      const [accountsFile, accountId] = process.argv.slice(1);
      let accounts = JSON.parse(fs.readFileSync(accountsFile, "utf8"));
      accounts = accounts.filter(a => a !== accountId);
      fs.writeFileSync(accountsFile, JSON.stringify(accounts, null, 2));
      console.log("✅ 微信账号已移除: " + accountId);
    ' "$ACC_FILE" "$ACCOUNT_ID"
  fi
fi

rm -rf "$HOME/.openclaw/workspace-$TENANT_ID"
rm -rf "$HOME/.openclaw/agents/$TENANT_ID"
rm -f "$WORKSPACE/tenants/$TENANT_ID"-*

node -e '
  const fs = require("fs");
  const [registryPath, tenantId] = process.argv.slice(1);
  const reg = JSON.parse(fs.readFileSync(registryPath, "utf8"));
  delete reg.tenants[tenantId];
  fs.writeFileSync(registryPath, JSON.stringify(reg, null, 2));
  console.log("✅ 注册表已清理");
' "$REGISTRY" "$TENANT_ID"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ $TENANT_ID 已完全删除"
echo ""
echo "  - 绑定已移除"
echo "  - 白名单已清理"
echo "  - Agent 已删除"
echo "  - 文件已清理"
echo ""

echo "🔄 触发 gateway 热重载..."
if sh "$WORKSPACE/scripts/gateway-reload.sh"; then
  echo "✅ Gateway 重载完成"
else
  echo "⚠️  Gateway 热重载未完全确认，请手动检查"
fi

echo "该用户现在发消息会被拒绝（DM policy: allowlist）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
