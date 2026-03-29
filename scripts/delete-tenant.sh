#!/bin/sh
# 删除子系统
# 用法: sh scripts/delete-tenant.sh <tenantId>

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
CONFIG="$HOME/.openclaw/openclaw.json"

TENANT_ID="${1:?用法: sh delete-tenant.sh <tenantId>}"

# 获取 accountId
ACCOUNT_ID=$(node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  if (reg.tenants['$TENANT_ID']) process.stdout.write(reg.tenants['$TENANT_ID'].accountId || '');
")

# 停止等待中的登录进程
PID_FILE="$WORKSPACE/tenants/${TENANT_ID}-login.pid"
if [ -f "$PID_FILE" ]; then
  PID=$(cat "$PID_FILE")
  kill "$PID" 2>/dev/null || true
  rm -f "$PID_FILE"
fi

# 移除 binding
node -e "
  const fs = require('fs');
  const config = JSON.parse(fs.readFileSync('$CONFIG', 'utf8'));
  if (config.bindings) {
    config.bindings = config.bindings.filter(b => b.agentId !== '$TENANT_ID');
    fs.writeFileSync('$CONFIG', JSON.stringify(config, null, 2));
  }
"

# 登出微信账号（静默）
if [ -n "$ACCOUNT_ID" ]; then
  # 直接清理账号文件，跳过交互式 logout
  ACCOUNT_PREFIX=$(echo "$ACCOUNT_ID" | sed 's/[^a-zA-Z0-9-]/_/g')
  rm -f "$HOME/.openclaw/extensions/openclaw-weixin/accounts/${ACCOUNT_PREFIX}".* 2>/dev/null || true
  # 从 accounts.json 移除
  node -e "
    try {
      const fs = require('fs');
      const path = '$HOME/.openclaw/extensions/openclaw-weixin/accounts.json';
      const list = JSON.parse(fs.readFileSync(path, 'utf8'));
      const filtered = list.filter(a => !a.startsWith('$ACCOUNT_PREFIX'));
      if (filtered.length !== list.length) fs.writeFileSync(path, JSON.stringify(filtered));
    } catch(e) {}
  "
fi

# 删除 agent
openclaw agents delete "$TENANT_ID" --force 2>/dev/null || true

# 清理注册表
node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  delete reg.tenants['$TENANT_ID'];
  fs.writeFileSync('$REGISTRY', JSON.stringify(reg, null, 2));
"

# 清理二维码
rm -f "$WORKSPACE/tenants/${TENANT_ID}-qr.png"

echo "✅ 已删除: $TENANT_ID"
echo "   重启 gateway 生效: openclaw gateway restart"
