#!/bin/sh
# 生成绑定二维码信息
# 用法: sh scripts/generate-bind-qr.sh <tenantId>
#
# 输出绑定信息（用于生成二维码或直接发送给朋友）

set -e

WORKSPACE="/home/node/.openclaw/workspace"
TENANTS_DIR="$WORKSPACE/tenants"

TENANT_ID="${1:?用法: sh generate-bind-qr.sh <tenantId>}"

META="$TENANTS_DIR/$TENANT_ID/.tenant-meta.json"

if [ ! -f "$META" ]; then
  echo "ERROR: 子系统 '$TENANT_ID' 不存在"
  exit 1
fi

# 读取元数据
node -e "
  const fs = require('fs');
  const meta = JSON.parse(fs.readFileSync('$META', 'utf8'));

  if (meta.bound) {
    console.log('⚠️  该子系统已绑定到: ' + meta.boundChatId);
    process.exit(0);
  }

  console.log('');
  console.log('📱 绑定信息');
  console.log('━━━━━━━━━━━━━━━━━━━━━━');
  console.log('子系统: ' + meta.displayName + ' (' + meta.tenantId + ')');
  console.log('绑定码: ' + meta.bindCode);
  console.log('');
  console.log('📋 绑定方式:');
  console.log('  朋友发送: bind:' + meta.bindCode);
  console.log('  或扫码绑定');
  console.log('');
  console.log('QR 内容（JSON）:');
  console.log(JSON.stringify({
    action: 'bind-tenant',
    tenantId: meta.tenantId,
    bindCode: meta.bindCode,
    displayName: meta.displayName
  }));
"
