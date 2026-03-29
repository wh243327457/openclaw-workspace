#!/bin/sh
# 创建子系统 + 生成微信绑定二维码
# 用法: sh scripts/create-tenant.sh [displayName]
#
# 自动完成：
# 1. 创建 OpenClaw agent（独立工作目录）
# 2. 初始化模板文件
# 3. 启动微信扫码登录，生成绑定二维码
# 4. 生成二维码图片
# 5. 扫码完成后自动获取真实 accountId 并更新绑定

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
TEMPLATE="$WORKSPACE/templates/tenant-default"
WX_ACCOUNTS_FILE="$HOME/.openclaw/openclaw-weixin/accounts.json"

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

echo "📦 创建子系统 $TENANT_ID ($DISPLAY_NAME)..."

# 1. 创建 OpenClaw agent
openclaw agents add "$TENANT_ID" --non-interactive --workspace "$AGENT_WORKSPACE" 2>&1 | grep -v "^Config\|^Updated\|^Workspace\|^Sessions\|^Agent:" || true

# 2. 初始化模板
for f in SOUL.md USER.md IDENTITY.md MEMORY.md HEARTBEAT.md AGENTS.md TOOLS.md cron.json; do
  [ -f "$TEMPLATE/$f" ] && cp "$TEMPLATE/$f" "$AGENT_WORKSPACE/$f"
done
cp -r "$TEMPLATE/memory" "$AGENT_WORKSPACE/memory" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/memory"
cp -r "$TEMPLATE/scripts" "$AGENT_WORKSPACE/scripts" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/scripts"

# 3. 记录登录前的账号列表（用于登录后检测新增）
EXISTING_ACCOUNTS=""
if [ -f "$WX_ACCOUNTS_FILE" ]; then
  EXISTING_ACCOUNTS=$(cat "$WX_ACCOUNTS_FILE")
fi

echo "✅ Agent 创建完成"
echo ""
echo "📱 正在生成微信绑定二维码..."
echo "   请让朋友准备好微信扫码"
echo ""

# 4. 启动微信登录（生成二维码）
LOGIN_LOG=$(mktemp)
openclaw channels login --channel openclaw-weixin > "$LOGIN_LOG" 2>&1 &
LOGIN_PID=$!

# 等待 QR URL 出现
QR_URL=""
for i in $(seq 1 30); do
  sleep 1
  if grep -q "https://liteapp.weixin.qq.com" "$LOGIN_LOG" 2>/dev/null; then
    QR_URL=$(grep -o "https://liteapp.weixin.qq.com/[^ ]*" "$LOGIN_LOG" | head -1)
    break
  fi
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
  echo "朋友扫码后运行: sh $WORKSPACE/scripts/finalize-tenant.sh $TENANT_ID"
  exit 0
fi

# 5. 从 URL 生成二维码图片
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

# 6. 写入注册表（accountId 暂为空，等扫码后更新）
node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  reg.tenants['$TENANT_ID'] = {
    displayName: '$DISPLAY_NAME',
    workspace: '$AGENT_WORKSPACE',
    accountId: null,
    bound: false,
    seq: $SEQ,
    createdAt: new Date().toISOString()
  };
  fs.writeFileSync('$REGISTRY', JSON.stringify(reg, null, 2));
"

# 7. 保存等待扫码完成的辅助信息
cat > "$WORKSPACE/tenants/$TENANT_ID-pending.json" <<EOF
{
  "tenantId": "$TENANT_ID",
  "existingAccounts": $EXISTING_ACCOUNTS,
  "loginPid": $LOGIN_PID,
  "loginLog": "$LOGIN_LOG"
}
EOF

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ 子系统 #$SEQ 已就绪（等待扫码）"
echo ""
echo "  ID:       $TENANT_ID"
echo "  名称:     $DISPLAY_NAME"
echo "  二维码:   $QR_FILE"
echo "  URL:      $QR_URL"
echo ""
echo "📋 下一步："
echo "  1. 把二维码图片发给朋友"
echo "  2. 朋友用微信扫码绑定"
echo "  3. 扫码后告诉我，我自动完成剩余配置"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "$LOGIN_PID" > "$WORKSPACE/tenants/$TENANT_ID-login.pid"
