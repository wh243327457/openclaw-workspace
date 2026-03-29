#!/bin/sh
# 创建子系统 + 自动生成二维码
# 用法: sh scripts/create-tenant.sh [displayName]
#
# 流程：
# 1. 创建 OpenClaw agent
# 2. 初始化模板文件
# 3. 生成二维码（编码 "bind:friend-NNN"）
# 4. 输出绑定指令

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

# 生成二维码
QR_FILE="$WORKSPACE/tenants/$TENANT_ID-qr.png"
node -e "
  try {
    const QRCode = require('/tmp/node_modules/qrcode');
    QRCode.toFile('$QR_FILE', 'bind:$TENANT_ID', {
      width: 300, margin: 2,
      color: { dark: '#000000', light: '#ffffff' }
    }, function(err) {
      if (!err) console.log('   二维码: 已生成');
    });
  } catch(e) { console.log('   二维码: 生成失败（需 npm install qrcode in /tmp）'); }
"

echo ""
echo "✅ 子系统 #$SEQ 创建成功"
echo "   ID:    $TENANT_ID"
echo "   名称:  $DISPLAY_NAME"
echo "   二维码: $QR_FILE"
echo ""
echo "📋 绑定流程："
echo "   1. 运行: sh scripts/bind-tenant.sh $TENANT_ID <朋友的open_id>"
echo "   2. 运行: openclaw gateway restart"
echo "   3. 把二维码图片发给朋友"
echo "   4. 朋友扫码发送 bind:$TENANT_ID → 消息直达 $TENANT_ID"
