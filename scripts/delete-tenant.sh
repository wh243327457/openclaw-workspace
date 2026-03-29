#!/bin/sh
# 删除子系统 + 清理绑定 + 清理白名单
# 用法: sh scripts/delete-tenant.sh <tenantId>

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
CONFIG="$HOME/.openclaw/openclaw.json"
ALLOW_FROM_FILE="$HOME/.openclaw/credentials/openclaw-weixin-allowFrom.json"
TENANT_ID="${1:-}"

if [ -z "$TENANT_ID" ]; then
  echo "用法: sh scripts/delete-tenant.sh <tenantId>"
  echo "例: sh scripts/delete-tenant.sh friend-001"
  exit 1
fi

echo "🗑️ 删除子系统 $TENANT_ID..."

# 1. 获取朋友的 peer ID（从会话记录）
PEER_ID=$(node -e "
  const fs = require('fs');
  const sessionsFile = '$HOME/.openclaw/agents/$TENANT_ID/sessions/sessions.json';
  if (fs.existsSync(sessionsFile)) {
    const sessions = JSON.parse(fs.readFileSync(sessionsFile, 'utf8'));
    for (const [k, v] of Object.entries(sessions)) {
      if (v.origin?.from) { console.log(v.origin.from); break; }
    }
  }
")

# 2. 从白名单移除
if [ -n "$PEER_ID" ] && [ -f "$ALLOW_FROM_FILE" ]; then
  node -e "
    const fs = require('fs');
    let list = JSON.parse(fs.readFileSync('$ALLOW_FROM_FILE', 'utf8'));
    const before = list.length;
    list = list.filter(id => id !== '$PEER_ID');
    if (list.length < before) {
      fs.writeFileSync('$ALLOW_FROM_FILE', JSON.stringify(list, null, 2));
      console.log('✅ 已从白名单移除: $PEER_ID');
    } else {
      console.log('ℹ️  不在白名单中');
    }
  "
fi

# 3. 移除绑定
node -e "
  const fs = require('fs');
  const config = JSON.parse(fs.readFileSync('$CONFIG', 'utf8'));
  config.bindings = (config.bindings||[]).filter(b => b.agentId !== '$TENANT_ID');
  fs.writeFileSync('$CONFIG', JSON.stringify(config, null, 2));
  console.log('✅ 绑定已移除');
"

# 4. 删除 agent
openclaw agents delete "$TENANT_ID" --force 2>&1 || true

# 5. 清理注册表
node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  delete reg.tenants['$TENANT_ID'];
  fs.writeFileSync('$REGISTRY', JSON.stringify(reg, null, 2));
  console.log('✅ 注册表已清理');
"

# 6. 删除文件
rm -rf "$HOME/.openclaw/workspace-$TENANT_ID"
rm -rf "$HOME/.openclaw/agents/$TENANT_ID"
rm -f "$WORKSPACE/tenants/$TENANT_ID"-*

# 7. 获取对应的微信账号并删除
ACCOUNT_ID=$(node -e "
  const fs = require('fs');
  const config = JSON.parse(fs.readFileSync('$CONFIG', 'utf8'));
  const binding = (config.bindings||[]).find(b => b.agentId === '$TENANT_ID');
  if (binding) console.log(binding.match.accountId);
" 2>/dev/null || true)

if [ -n "$ACCOUNT_ID" ]; then
  # 从 accounts.json 移除
  ACC_FILE="$HOME/.openclaw/openclaw-weixin/accounts.json"
  if [ -f "$ACC_FILE" ]; then
    node -e "
      const fs = require('fs');
      let accounts = JSON.parse(fs.readFileSync('$ACC_FILE', 'utf8'));
      accounts = accounts.filter(a => a !== '$ACCOUNT_ID');
      fs.writeFileSync('$ACC_FILE', JSON.stringify(accounts, null, 2));
      console.log('✅ 微信账号已移除: $ACCOUNT_ID');
    "
  fi
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ $TENANT_ID 已完全删除"
echo ""
echo "  - 绑定已移除"
echo "  - 白名单已清理"
echo "  - Agent 已删除"
echo "  - 文件已清理"
echo ""

# 触发 gateway 重载
sh "$WORKSPACE/scripts/gateway-reload.sh"

echo "该用户现在发消息会被拒绝（DM policy: allowlist）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
