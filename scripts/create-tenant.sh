#!/bin/sh
# 创建子系统
# 用法: sh scripts/create-tenant.sh [displayName]
#
# 自动编号: friend-001, friend-002, ...
# 不传名称则默认 "朋友 #NNN"

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
TEMPLATE="$WORKSPACE/templates/tenant-default"

# 自动编号
SEQ=$(node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  const nums = Object.keys(reg.tenants).filter(k => k.startsWith('friend-')).map(k => parseInt(k.split('-')[1])).filter(n => !isNaN(n));
  console.log(String((nums.length > 0 ? Math.max(...nums) : 0) + 1).padStart(3, '0'));
")

TENANT_ID="friend-$SEQ"
DISPLAY_NAME="${1:-朋友 #$SEQ}"
AGENT_WORKSPACE="$HOME/.openclaw/workspace-$TENANT_ID"

# 创建 OpenClaw agent
openclaw agents add "$TENANT_ID" --non-interactive --workspace "$AGENT_WORKSPACE"

# 初始化模板
for f in SOUL.md USER.md IDENTITY.md MEMORY.md HEARTBEAT.md AGENTS.md TOOLS.md cron.json; do
  [ -f "$TEMPLATE/$f" ] && cp "$TEMPLATE/$f" "$AGENT_WORKSPACE/$f"
done
cp -r "$TEMPLATE/memory" "$AGENT_WORKSPACE/memory" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/memory"
cp -r "$TEMPLATE/scripts" "$AGENT_WORKSPACE/scripts" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/scripts"

# 写入注册表
node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  reg.tenants['$TENANT_ID'] = {
    displayName: '$DISPLAY_NAME',
    workspace: '$AGENT_WORKSPACE',
    bound: false,
    boundPeerId: null,
    seq: $SEQ,
    createdAt: new Date().toISOString()
  };
  fs.writeFileSync('$REGISTRY', JSON.stringify(reg, null, 2));
"

echo "✅ 子系统 #$SEQ 创建成功"
echo "   ID:    $TENANT_ID"
echo "   名称:  $DISPLAY_NAME"
echo ""
echo "下一步：让朋友在微信里给我发条消息，拿到 open_id 后运行："
echo "   sh scripts/bind-tenant.sh $TENANT_ID <朋友的open_id>"
