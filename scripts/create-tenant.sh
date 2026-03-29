#!/bin/sh
# 创建子系统（使用 OpenClaw 原生 agents）
# 用法: sh scripts/create-tenant.sh <tenantId> [displayName]
#
# 自动完成：
# 1. 创建 OpenClaw agent（独立工作目录）
# 2. 初始化模板文件
# 3. 写入注册表
# 4. 生成绑定码

set -e

WORKSPACE="/home/node/.openclaw/workspace"
TENANTS_DIR="$WORKSPACE/tenants"
REGISTRY="$TENANTS_DIR/registry.json"
TEMPLATE="$WORKSPACE/templates/tenant-default"

TENANT_ID="${1:?用法: sh create-tenant.sh <tenantId> [displayName]}"
DISPLAY_NAME="${2:-$TENANT_ID}"

# 校验 tenantId 格式
echo "$TENANT_ID" | grep -qE '^[a-z0-9][a-z0-9-]*[a-z0-9]$' || {
  echo "ERROR: tenantId 只能包含小写字母、数字和连字符，且不能以连字符开头或结尾"
  exit 1
}

AGENT_WORKSPACE="$HOME/.openclaw/workspace-$TENANT_ID"

# 检查是否已存在
if [ -d "$AGENT_WORKSPACE" ]; then
  echo "ERROR: 工作目录已存在: $AGENT_WORKSPACE"
  exit 1
fi

# 第1步：创建 OpenClaw agent
echo "创建 OpenClaw agent: $TENANT_ID"
openclaw agents add "$TENANT_ID" --non-interactive --workspace "$AGENT_WORKSPACE"

# 第2步：复制模板文件到 agent 工作目录
echo "初始化模板文件..."
for f in SOUL.md USER.md IDENTITY.md MEMORY.md HEARTBEAT.md AGENTS.md TOOLS.md cron.json; do
  if [ -f "$TEMPLATE/$f" ]; then
    cp "$TEMPLATE/$f" "$AGENT_WORKSPACE/$f"
  fi
done
# 复制子目录
cp -r "$TEMPLATE/memory" "$AGENT_WORKSPACE/memory" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/memory"
cp -r "$TEMPLATE/scripts" "$AGENT_WORKSPACE/scripts" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/scripts"

# 第3步：生成绑定码
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
    createdAt: new Date().toISOString()
  };
  fs.writeFileSync('$TMP', JSON.stringify(reg, null, 2));
" && mv "$TMP" "$REGISTRY"

echo ""
echo "✅ 子系统创建成功"
echo "   ID:        $TENANT_ID"
echo "   名称:      $DISPLAY_NAME"
echo "   工作目录:  $AGENT_WORKSPACE"
echo "   绑定码:    $BIND_CODE"
echo ""
echo "下一步：朋友发送绑定码后，运行 bind-tenant 完成关联"
echo "或运行: sh scripts/generate-bind-qr.sh $TENANT_ID 生成绑定信息"
