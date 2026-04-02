#!/bin/sh
# 创建子系统（阶段 1：创建 agent + 初始化模板）
# 用法:
#   sh scripts/create-tenant.sh [displayName]
#   sh scripts/create-tenant.sh [displayName] --no-qr

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
TEMPLATE="$WORKSPACE/templates/tenant-default"

AUTO_QR="true"
DISPLAY_NAME_ARG=""

for arg in "$@"; do
  case "$arg" in
    --with-qr)
      AUTO_QR="true"
      ;;
    --no-qr)
      AUTO_QR="false"
      ;;
    *)
      if [ -z "$DISPLAY_NAME_ARG" ]; then
        DISPLAY_NAME_ARG="$arg"
      else
        echo "用法: sh scripts/create-tenant.sh [displayName] [--no-qr]"
        exit 1
      fi
      ;;
  esac
done

mkdir -p "$WORKSPACE/tenants"

if [ -n "$OWNER_PEER" ]; then
  echo "📌 OWNER_PEER 从环境变量读取: $OWNER_PEER"
else
  OWNER_PEER=$(node -e "
    const fs = require('fs');
    try {
      const reg = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
      console.log(reg.ownerPeer || '');
    } catch (error) {
      console.log('');
    }
  " "$REGISTRY" 2>/dev/null)
fi

if [ -z "$OWNER_PEER" ]; then
  echo "⚠️  未找到 ownerPeer 配置，继续以本地出码模式运行"
fi

SEQ=$(node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
  const tenants = reg.tenants || {};
  const nums = Object.keys(tenants)
    .filter((key) => key.startsWith('friend-'))
    .map((key) => parseInt(key.split('-')[1], 10))
    .filter((num) => !Number.isNaN(num));
  console.log(String((nums.length > 0 ? Math.max(...nums) : 0) + 1).padStart(3, '0'));
" "$REGISTRY")

TENANT_ID="friend-$SEQ"
DISPLAY_NAME="${DISPLAY_NAME_ARG:-朋友 #$SEQ}"
AGENT_WORKSPACE="$HOME/.openclaw/workspace-$TENANT_ID"

PENDING_FILE="$WORKSPACE/tenants/${TENANT_ID}-pending.json"
rm -f "$PENDING_FILE"

echo "📦 创建子系统 $TENANT_ID ($DISPLAY_NAME)..."
echo ""
echo "── 阶段 1/1：创建 agent ──"

ADD_OUTPUT=$(openclaw agents add "$TENANT_ID" --non-interactive --workspace "$AGENT_WORKSPACE" 2>&1) || {
  echo "$ADD_OUTPUT" | grep -v "^Config\|^Updated\|^Workspace\|^Sessions\|^Agent:" || true
  echo "❌ Agent 创建失败"
  echo "   恢复建议: 检查 openclaw agents list，确认 $TENANT_ID 是否已存在"
  exit 1
}
echo "$ADD_OUTPUT" | grep -v "^Config\|^Updated\|^Workspace\|^Sessions\|^Agent:" || true

for f in SOUL.md USER.md IDENTITY.md MEMORY.md HEARTBEAT.md AGENTS.md TOOLS.md cron.json; do
  [ -f "$TEMPLATE/$f" ] && cp "$TEMPLATE/$f" "$AGENT_WORKSPACE/$f"
done
cp -r "$TEMPLATE/memory" "$AGENT_WORKSPACE/memory" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/memory"
cp -r "$TEMPLATE/scripts" "$AGENT_WORKSPACE/scripts" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/scripts"

node -e "
  const fs = require('fs');
  const [registryPath, tenantId, displayName, workspacePath, seq, ownerPeer] = process.argv.slice(1);
  const reg = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
  if (!reg.tenants) reg.tenants = {};
  reg.ownerPeer = ownerPeer;
  reg.tenants[tenantId] = {
    displayName,
    workspace: workspacePath,
    bound: false,
    seq: Number(seq),
    createdAt: new Date().toISOString()
  };
  fs.writeFileSync(registryPath, JSON.stringify(reg, null, 2));
" "$REGISTRY" "$TENANT_ID" "$DISPLAY_NAME" "$AGENT_WORKSPACE" "$SEQ" "$OWNER_PEER"

echo "✅ Agent $TENANT_ID 创建完成"
echo "✅ ownerPeer 已保存到 registry.json"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 $TENANT_ID ($DISPLAY_NAME) 创建完成！"
echo ""
echo "  阶段 1: 已创建 agent + 初始化 workspace"
echo "  阶段 2: 自动生成二维码并返回给主人"
echo "  阶段 3: 朋友扫码后后台自动完成绑定"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$AUTO_QR" = "true" ]; then
  echo ""
  echo "▶️  继续进入阶段 2：生成二维码"
  sh "$WORKSPACE/scripts/generate-tenant-qr.sh" "$TENANT_ID"
fi
