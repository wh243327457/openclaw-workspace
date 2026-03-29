#!/bin/sh
# 生成绑定信息（发送给朋友）
# 用法: sh scripts/generate-bind-qr.sh <tenantId>

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"

TENANT_ID="${1:?用法: sh generate-bind-qr.sh <tenantId>}"

# 读取注册表信息
node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  const t = reg.tenants['$TENANT_ID'];
  if (!t) { console.log('ERROR: 子系统不存在: $TENANT_ID'); process.exit(1); }
  if (t.bound) { console.log('⚠️  已绑定到: ' + t.boundPeerId); process.exit(0); }

  console.log('');
  console.log('📱 绑定信息');
  console.log('━━━━━━━━━━━━━━━━━━━━━━');
  console.log('子系统: ' + t.displayName);
  console.log('');
  console.log('请发送以下内容完成绑定:');
  console.log('');
  console.log('  bind:' + t.bindCode);
  console.log('');
  console.log('或直接告诉我绑定码，我帮你关联。');
"
