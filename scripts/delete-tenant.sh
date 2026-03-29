#!/bin/sh
# 删除子系统
# 用法: sh scripts/delete-tenant.sh <tenantId>

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
CONFIG="$HOME/.openclaw/openclaw.json"

TENANT_ID="${1:?用法: sh delete-tenant.sh <tenantId>}"

# 移除 binding
node -e "
  const fs = require('fs');
  const config = JSON.parse(fs.readFileSync('$CONFIG', 'utf8'));
  if (config.bindings) {
    config.bindings = config.bindings.filter(b => b.agentId !== '$TENANT_ID');
    fs.writeFileSync('$CONFIG', JSON.stringify(config, null, 2));
  }
"

# 删除 agent
openclaw agents delete "$TENANT_ID" --force 2>/dev/null || true

# 清理注册表
node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  delete reg.tenants['$TENANT_ID'];
  fs.writeFileSync('$REGISTRY', JSON.stringify(reg, null, 2));
"

echo "✅ 已删除: $TENANT_ID"
echo "   重启 gateway 生效: openclaw gateway restart"
