#!/bin/sh
# 删除子系统
# 用法: sh scripts/delete-tenant.sh <tenantId>
#
# 自动完成：
# 1. 移除 openclaw.json 中的 binding
# 2. 删除 OpenClaw agent
# 3. 清理注册表

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
CONFIG="$HOME/.openclaw/openclaw.json"

TENANT_ID="${1:?用法: sh delete-tenant.sh <tenantId>}"

# 检查是否存在
EXISTS=$(node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  console.log(reg.tenants['$TENANT_ID'] ? 'true' : 'false');
")
if [ "$EXISTS" != "true" ]; then
  echo "ERROR: 子系统不存在: $TENANT_ID"
  exit 1
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

# 删除 OpenClaw agent
openclaw agents delete "$TENANT_ID" --force 2>/dev/null || echo "  (agent 删除跳过)"

# 清理注册表
node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  delete reg.tenants['$TENANT_ID'];
  fs.writeFileSync('$REGISTRY', JSON.stringify(reg, null, 2));
"

echo "✅ 子系统已删除: $TENANT_ID"
echo "   ⚠️  请重启 gateway 生效: openclaw gateway restart"
