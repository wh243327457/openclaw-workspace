#!/bin/sh
# 创建子系统（自动生成 ID + 序号）
# 用法: sh scripts/create-tenant.sh [displayName]
#
# 如果不提供 displayName，自动生成 "朋友 #N"
# tenantId 自动生成为 friend-NNN 格式

set -e

WORKSPACE="/home/node/.openclaw/workspace"
TENANTS_DIR="$WORKSPACE/tenants"
REGISTRY="$TENANTS_DIR/registry.json"
TEMPLATE="$WORKSPACE/templates/tenant-default"

# 读取当前计数，自动生成下一个序号
SEQ=$(node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  const ids = Object.keys(reg.tenants).filter(k => k.match(/^friend-/));
  const nums = ids.map(k => parseInt(k.replace('friend-', ''))).filter(n => !isNaN(n));
  const max = nums.length > 0 ? Math.max(...nums) : 0;
  console.log(String(max + 1).padStart(3, '0'));
")

TENANT_ID="friend-$SEQ"
DISPLAY_NAME="${1:-朋友 #$SEQ}"

AGENT_WORKSPACE="$HOME/.openclaw/workspace-$TENANT_ID"

echo "创建子系统: $TENANT_ID ($DISPLAY_NAME)"

# 创建 OpenClaw agent
openclaw agents add "$TENANT_ID" --non-interactive --workspace "$AGENT_WORKSPACE"

# 初始化模板文件
for f in SOUL.md USER.md IDENTITY.md MEMORY.md HEARTBEAT.md AGENTS.md TOOLS.md cron.json; do
  [ -f "$TEMPLATE/$f" ] && cp "$TEMPLATE/$f" "$AGENT_WORKSPACE/$f"
done
cp -r "$TEMPLATE/memory" "$AGENT_WORKSPACE/memory" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/memory"
cp -r "$TEMPLATE/scripts" "$AGENT_WORKSPACE/scripts" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/scripts"

# 生成绑定码
BIND_CODE=$(cat /dev/urandom | tr -dc 'A-Z0-9' | head -c 6)

# 写入注册表
TMP=$(mktemp)
node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  reg.tenants['$TENANT_ID'] = {
    displayName: '$DISPLAY_NAME',
    workspace: '$AGENT_WORKSPACE',
    bindCode: '$BIND_CODE',
    bound: false,
    boundPeerId: null,
    seq: $SEQ,
    createdAt: new Date().toISOString()
  };
  fs.writeFileSync('$TMP', JSON.stringify(reg, null, 2));
" && mv "$TMP" "$REGISTRY"

echo ""
echo "✅ 子系统 #$SEQ 创建成功"
echo "   ID:        $TENANT_ID"
echo "   名称:      $DISPLAY_NAME"
echo "   绑定码:    $BIND_CODE"
echo ""
echo "📱 发给朋友的绑定信息:"
echo "━━━━━━━━━━━━━━━━━━━━━━"
echo "   发送 bind:$BIND_CODE 完成绑定"
echo ""
echo "朋友绑定后，运行:"
echo "   sh scripts/bind-tenant.sh $BIND_CODE <朋友的open_id>"
