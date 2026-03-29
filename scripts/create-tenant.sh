#!/bin/sh
# 创建子系统 + 生成微信绑定二维码
# 用法: sh scripts/create-tenant.sh [displayName]
#
# 自动完成：
# 1. 创建 OpenClaw agent（独立工作目录）
# 2. 初始化模板文件
# 3. 启动微信扫码登录，生成绑定二维码
# 4. 生成二维码图片

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
ACCOUNT_ID="$TENANT_ID"

echo "📦 创建子系统 $TENANT_ID ($DISPLAY_NAME)..."

# 1. 创建 OpenClaw agent
openclaw agents add "$TENANT_ID" --non-interactive --workspace "$AGENT_WORKSPACE" 2>&1 | grep -v "^Config\|^Updated\|^Workspace\|^Sessions\|^Agent:" || true

# 2. 初始化模板
for f in SOUL.md USER.md IDENTITY.md MEMORY.md HEARTBEAT.md AGENTS.md TOOLS.md cron.json; do
  [ -f "$TEMPLATE/$f" ] && cp "$TEMPLATE/$f" "$AGENT_WORKSPACE/$f"
done
cp -r "$TEMPLATE/memory" "$AGENT_WORKSPACE/memory" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/memory"
cp -r "$TEMPLATE/scripts" "$AGENT_WORKSPACE/scripts" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/scripts"

# 3. 写入注册表
node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  reg.tenants['$TENANT_ID'] = {
    displayName: '$DISPLAY_NAME',
    workspace: '$AGENT_WORKSPACE',
    accountId: '$ACCOUNT_ID',
    bound: false,
    seq: $SEQ,
    createdAt: new Date().toISOString()
  };
  fs.writeFileSync('$REGISTRY', JSON.stringify(reg, null, 2));
"

# 4. 添加 binding（按 accountId 路由）
CONFIG="$HOME/.openclaw/openclaw.json"
node -e "
  const fs = require('fs');
  const config = JSON.parse(fs.readFileSync('$CONFIG', 'utf8'));
  if (!config.bindings) config.bindings = [];
  config.bindings.push({
    agentId: '$TENANT_ID',
    match: {
      channel: 'openclaw-weixin',
      accountId: '$ACCOUNT_ID'
    }
  });
  fs.writeFileSync('$CONFIG', JSON.stringify(config, null, 2));
"

echo "✅ Agent 创建完成"
echo ""
echo "📱 正在生成微信绑定二维码..."
echo "   请让朋友准备好微信扫码"
echo ""

# 5. 启动微信登录（生成二维码）
# 在后台运行，捕获 QR URL
LOGIN_LOG=$(mktemp)
openclaw channels login --channel openclaw-weixin --account "$ACCOUNT_ID" > "$LOGIN_LOG" 2>&1 &
LOGIN_PID=$!

# 等待 QR URL 出现
QR_URL=""
for i in $(seq 1 30); do
  sleep 1
  if grep -q "https://liteapp.weixin.qq.com" "$LOGIN_LOG" 2>/dev/null; then
    QR_URL=$(grep -o "https://liteapp.weixin.qq.com/[^ ]*" "$LOGIN_LOG" | head -1)
    break
  fi
  # 也检查 terminal QR code 后的 URL
  if grep -q "qrcode=" "$LOGIN_LOG" 2>/dev/null; then
    QR_URL=$(grep -o "https://[^ ]*qrcode=[^ ]*" "$LOGIN_LOG" | head -1)
    break
  fi
done

if [ -z "$QR_URL" ]; then
  echo "⚠️  无法自动获取二维码，请手动扫码："
  cat "$LOGIN_LOG"
  echo ""
  echo "登录命令仍在后台运行 (PID: $LOGIN_PID)"
  echo "朋友扫码后运行: openclaw gateway restart"
  exit 0
fi

# 6. 从 URL 生成二维码图片
QR_FILE="$WORKSPACE/tenants/$TENANT_ID-qr.png"
node -e "
  try {
    const QRCode = require('/tmp/node_modules/qrcode');
    QRCode.toFile('$QR_FILE', '$QR_URL', {
      width: 400, margin: 2,
      color: { dark: '#000000', light: '#ffffff' }
    }, function(err) {
      if (!err) console.log('✅ 二维码图片已生成: $QR_FILE');
    });
  } catch(e) {
    console.log('⚠️  二维码图片生成失败，请使用 URL:');
    console.log('$QR_URL');
  }
"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 子系统 #$SEQ 已就绪"
echo ""
echo "  ID:       $TENANT_ID"
echo "  名称:     $DISPLAY_NAME"
echo "  二维码:   $QR_FILE"
echo "  URL:      $QR_URL"
echo ""
echo "📋 下一步："
echo "  1. 把二维码图片发给朋友"
echo "  2. 朋友用微信扫码绑定"
echo "  3. 扫码成功后运行: openclaw gateway restart"
echo "  4. 朋友发消息 → 自动进入 $TENANT_ID 系统"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "⏳ 微信登录进程在后台等待 (PID: $LOGIN_PID)"
echo "   朋友扫码后会自动完成，然后重启 gateway 即可"
echo ""
echo "$LOGIN_PID" > "$WORKSPACE/tenants/$TENANT_ID-login.pid"
