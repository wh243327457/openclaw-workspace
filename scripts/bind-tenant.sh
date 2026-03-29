#!/bin/sh
# 手动绑定（备用，通常不需要）
# 正常流程：create-tenant 自动生成绑定 + 二维码
# 此脚本仅在需要重新绑定时使用
# 用法: sh scripts/bind-tenant.sh <tenantId> <open_id>

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
CONFIG="$HOME/.openclaw/openclaw.json"

TENANT_ID="${1:?用法: sh bind-tenant.sh <tenantId> <peerId>}"
PEER_ID="${2:?需要提供朋友的 open_id}"

# 添加 peer 级 binding（优先级高于 accountId 级）
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
node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  if (reg.tenants['$TENANT_ID']) {
    reg.tenants['$TENANT_ID'].bound = true;
    reg.tenants['$TENANT_ID'].boundPeerId = '$PEER_ID';
    reg.tenants['$TENANT_ID'].boundAt = new Date().toISOString();
    fs.writeFileSync('$REGISTRY', JSON.stringify(reg, null, 2));
  }
"

echo "✅ 手动绑定成功: $TENANT_ID ← $PEER_ID"
echo "   重启 gateway 生效: openclaw gateway restart"
