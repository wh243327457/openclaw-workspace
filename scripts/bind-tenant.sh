#!/bin/sh
# 绑定子系统到聊天
# 用法: sh scripts/bind-tenant.sh <bindCode> <chatId>
#
# bindCode: 创建时生成的6位绑定码
# chatId: 绑定的聊天ID（微信 open_id 等）

set -e

WORKSPACE="/home/node/.openclaw/workspace"
TENANTS_DIR="$WORKSPACE/tenants"
REGISTRY="$TENANTS_DIR/registry.json"

BIND_CODE="${1:?用法: sh bind-tenant.sh <bindCode> <chatId>}"
CHAT_ID="${2:?需要提供 chatId}"

# 查找匹配的绑定码
FOUND=""
for dir in "$TENANTS_DIR"/*/; do
  META="$dir/.tenant-meta.json"
  [ -f "$META" ] || continue
  CODE=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$META','utf8')).bindCode)")
  if [ "$CODE" = "$BIND_CODE" ]; then
    FOUND="$dir"
    break
  fi
done

if [ -z "$FOUND" ]; then
  echo "ERROR: 绑定码无效: $BIND_CODE"
  exit 1
fi

META="$FOUND/.tenant-meta.json"
TENANT_ID=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$META','utf8')).tenantId)")

# 检查是否已绑定
BOUND=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$META','utf8')).bound)")
if [ "$BOUND" = "true" ]; then
  EXISTING=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$META','utf8')).boundChatId)")
  echo "ERROR: 该子系统已绑定到 $EXISTING"
  exit 1
fi

# 检查 chatId 是否已绑定其他租户
for dir in "$TENANTS_DIR"/*/; do
  M="$dir/.tenant-meta.json"
  [ -f "$M" ] || continue
  CID=$(node -e "const m=JSON.parse(require('fs').readFileSync('$M','utf8')); console.log(m.boundChatId||'')")
  if [ "$CID" = "$CHAT_ID" ]; then
    EXIST_ID=$(node -e "console.log(JSON.parse(require('fs').readFileSync('$M','utf8')).tenantId)")
    echo "ERROR: 该聊天已绑定子系统: $EXIST_ID"
    exit 1
  fi
done

# 执行绑定
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
node -e "
  const fs = require('fs');
  const meta = JSON.parse(fs.readFileSync('$META', 'utf8'));
  meta.bound = true;
  meta.boundChatId = '$CHAT_ID';
  meta.boundAt = '$NOW';
  fs.writeFileSync('$META', JSON.stringify(meta, null, 2));

  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  reg.tenants['$TENANT_ID'].bound = true;
  reg.tenants['$TENANT_ID'].boundChatId = '$CHAT_ID';
  fs.writeFileSync('$REGISTRY', JSON.stringify(reg, null, 2));

  // 更新路由表
  const routingPath = '$WORKSPACE/tenants/routing.json';
  const routing = JSON.parse(fs.readFileSync(routingPath, 'utf8'));
  routing.routes['$CHAT_ID'] = '$TENANT_ID';
  fs.writeFileSync(routingPath, JSON.stringify(routing, null, 2));
"

echo "✅ 绑定成功"
echo "   子系统: $TENANT_ID"
echo "   聊天ID: $CHAT_ID"
echo "   时间:   $NOW"
