#!/bin/sh
# 绑定朋友到子系统
# 用法: sh scripts/bind-tenant.sh <tenantId> <peerId>
#
# tenantId: 子系统 ID（如 friend-001）
# peerId: 朋友的微信 open_id
#
# 自动在 openclaw.json 中添加 peer 路由

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
CONFIG="$HOME/.openclaw/openclaw.json"

TENANT_ID="${1:?用法: sh bind-tenant.sh <tenantId> <peerId>}"
PEER_ID="${2:?需要提供朋友的 open_id}"

# 检查租户是否存在
EXISTS=$(node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  console.log(reg.tenants['$TENANT_ID'] ? 'yes' : 'no');
")
[ "$EXISTS" = "yes" ] || { echo "ERROR: 子系统不存在: $TENANT_ID"; exit 1; }

# 检查是否已绑定
BOUND=$(node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  console.log(reg.tenants['$TENANT_ID'].bound);
")
[ "$BOUND" != "true" ] || { echo "ERROR: $TENANT_ID 已绑定"; exit 1; }

# 添加 binding 到 openclaw.json
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

echo "✅ 绑定成功: $TENANT_ID ← $PEER_ID"
echo ""
echo "重启 gateway 生效："
echo "   openclaw gateway restart"
