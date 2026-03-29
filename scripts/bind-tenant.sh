#!/bin/sh
# 绑定子系统到朋友的聊天
# 用法: sh scripts/bind-tenant.sh <bindCode> <peerId>
#
# bindCode: 创建时生成的6位绑定码
# peerId: 朋友的微信 open_id
#
# 自动完成：
# 1. 验证绑定码
# 2. 在 openclaw.json 中添加 peer 路由 binding
# 3. 更新注册表
# 4. 重启 gateway 生效

set -e

WORKSPACE="/home/node/.openclaw/workspace"
TENANTS_DIR="$WORKSPACE/tenants"
REGISTRY="$TENANTS_DIR/registry.json"
CONFIG="$HOME/.openclaw/openclaw.json"

BIND_CODE="${1:?用法: sh bind-tenant.sh <bindCode> <peerId>}"
PEER_ID="${2:?需要提供 peerId（朋友的微信 open_id）}"

# 查找匹配绑定码的租户
TENANT_ID=""
for tid in $(node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  Object.keys(reg.tenants).forEach(id => {
    if (reg.tenants[id].bindCode === '$BIND_CODE') console.log(id);
  });
"); do
  TENANT_ID="$tid"
done

if [ -z "$TENANT_ID" ]; then
  echo "ERROR: 绑定码无效: $BIND_CODE"
  exit 1
fi

# 检查是否已绑定
BOUND=$(node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  console.log(reg.tenants['$TENANT_ID'].bound);
")
if [ "$BOUND" = "true" ]; then
  EXISTING=$(node -e "
    const fs = require('fs');
    const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
    console.log(reg.tenants['$TENANT_ID'].boundPeerId);
  ")
  echo "ERROR: 该子系统已绑定到: $EXISTING"
  exit 1
fi

# 检查 peerId 是否已绑定其他租户
EXISTING_PEER=$(node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  Object.keys(reg.tenants).forEach(id => {
    if (reg.tenants[id].boundPeerId === '$PEER_ID') console.log(id);
  });
")
if [ -n "$EXISTING_PEER" ]; then
  echo "ERROR: 该聊天已绑定子系统: $EXISTING_PEER"
  exit 1
fi

# 在 openclaw.json 中添加 binding
node -e "
  const fs = require('fs');
  const config = JSON.parse(fs.readFileSync('$CONFIG', 'utf8'));
  if (!config.bindings) config.bindings = [];
  config.bindings.push({
    agentId: '$TENANT_ID',
    match: {
      channel: 'openclaw-weixin',
      peer: { kind: 'direct', id: '$PEER_ID' }
    }
  });
  fs.writeFileSync('$CONFIG', JSON.stringify(config, null, 2));
"

# 更新注册表
NOW=$(date -u +%Y-%m-%dT%H:%M:%SZ)
node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  reg.tenants['$TENANT_ID'].bound = true;
  reg.tenants['$TENANT_ID'].boundPeerId = '$PEER_ID';
  reg.tenants['$TENANT_ID'].boundAt = '$NOW';
  fs.writeFileSync('$REGISTRY', JSON.stringify(reg, null, 2));
"

echo "✅ 绑定成功"
echo "   子系统:   $TENANT_ID"
echo "   朋友ID:   $PEER_ID"
echo "   时间:     $NOW"
echo ""
echo "⚠️  需要重启 gateway 才能生效:"
echo "   openclaw gateway restart"
