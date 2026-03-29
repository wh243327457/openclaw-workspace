#!/bin/sh
# 创建子系统（全自动流程）
# 用法: sh scripts/create-tenant.sh [displayName]
#
# 流程：
# 1. 创建 agent + 初始化模板
# 2. 启动微信登录，立即获取新 accountId
# 3. 写入绑定 + 重启 gateway（朋友扫码前完成）
# 4. 生成二维码发给主人
# 5. 朋友扫码时 gateway 已经是新配置 → 消息直接进子系统

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
TEMPLATE="$WORKSPACE/templates/tenant-default"
WX_ACCOUNTS_FILE="$HOME/.openclaw/openclaw-weixin/accounts.json"
CONFIG="$HOME/.openclaw/openclaw.json"
ALLOW_FROM_FILE="$HOME/.openclaw/credentials/openclaw-weixin-allowFrom.json"
OWNER_PEER="o9cq80-muALNTe-JpyCF5hb_v6GE@im.wechat"

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
echo ""

# ──── 阶段 1：创建 agent ────
openclaw agents add "$TENANT_ID" --non-interactive --workspace "$AGENT_WORKSPACE" 2>&1 | grep -v "^Config\|^Updated\|^Workspace\|^Sessions\|^Agent:" || true

for f in SOUL.md USER.md IDENTITY.md MEMORY.md HEARTBEAT.md AGENTS.md TOOLS.md cron.json; do
  [ -f "$TEMPLATE/$f" ] && cp "$TEMPLATE/$f" "$AGENT_WORKSPACE/$f"
done
cp -r "$TEMPLATE/memory" "$AGENT_WORKSPACE/memory" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/memory"
cp -r "$TEMPLATE/scripts" "$AGENT_WORKSPACE/scripts" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/scripts"

echo "✅ Agent 创建完成"

# ──── 阶段 2：启动微信登录，获取新 accountId ────
echo ""
echo "📱 启动微信登录..."

BEFORE=$(cat "$WX_ACCOUNTS_FILE" 2>/dev/null || echo "[]")

LOGIN_LOG=$(mktemp)
openclaw channels login --channel openclaw-weixin > "$LOGIN_LOG" 2>&1 &
LOGIN_PID=$!

# 等待新账号出现（登录进程启动后 accounts.json 会立即新增）
NEW_ACCOUNT=""
for i in $(seq 1 30); do
  sleep 1
  CURRENT=$(cat "$WX_ACCOUNTS_FILE" 2>/dev/null || echo "[]")
  if [ "$CURRENT" != "$BEFORE" ]; then
    NEW_ACCOUNT=$(node -e "
      const b = JSON.parse(process.argv[1]);
      const c = JSON.parse(process.argv[2]);
      const n = c.filter(id => !b.includes(id));
      console.log(n[0]||'');
    " "$BEFORE" "$CURRENT")
    break
  fi
  # 同时检查二维码是否已生成
  if grep -q "qrcode=" "$LOGIN_LOG" 2>/dev/null; then
    # 二维码已出但账号还没写入？继续等
    :
  fi
done

if [ -z "$NEW_ACCOUNT" ]; then
  echo "❌ 无法获取新账号"
  kill "$LOGIN_PID" 2>/dev/null || true
  exit 1
fi

echo "✅ 新账号: $NEW_ACCOUNT"

# ──── 阶段 3：写入绑定（朋友还没扫码） ────
node -e "
  const fs = require('fs');
  const config = JSON.parse(fs.readFileSync('$CONFIG', 'utf8'));
  config.bindings = (config.bindings||[]).filter(b => b.agentId !== '$TENANT_ID');
  config.bindings.push({
    agentId: '$TENANT_ID',
    match: { channel: 'openclaw-weixin', accountId: '$NEW_ACCOUNT' }
  });
  fs.writeFileSync('$CONFIG', JSON.stringify(config, null, 2));

  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  reg.tenants['$TENANT_ID'] = {
    displayName: '$DISPLAY_NAME',
    workspace: '$AGENT_WORKSPACE',
    accountId: '$NEW_ACCOUNT',
    bound: true,
    seq: $SEQ,
    createdAt: new Date().toISOString()
  };
  fs.writeFileSync('$REGISTRY', JSON.stringify(reg, null, 2));
"
echo "✅ 绑定已写入: $NEW_ACCOUNT → $TENANT_ID"

# ──── 阶段 4：触发 gateway 重载 ────
echo ""
echo "🔄 触发 gateway 热重载..."
sh "$WORKSPACE/scripts/gateway-reload.sh"

# ──── 阶段 5：等二维码生成，发给主人 ────
echo ""
echo "⏳ 等待二维码生成..."
QR_URL=""
for i in $(seq 1 20); do
  sleep 1
  if grep -q "qrcode=" "$LOGIN_LOG" 2>/dev/null; then
    QR_URL=$(grep -o "https://[^ ]*qrcode=[^ ]*" "$LOGIN_LOG" | head -1)
    break
  fi
done

if [ -z "$QR_URL" ]; then
  echo "❌ 二维码生成失败"
  kill "$LOGIN_PID" 2>/dev/null || true
  exit 1
fi

QR_FILE="$WORKSPACE/tenants/$TENANT_ID-qr.png"
node -e "
const QRCode = require('/tmp/node_modules/qrcode');
QRCode.toFile('$QR_FILE', '$QR_URL', {
  width: 400, margin: 2,
  color: { dark: '#000000', light: '#ffffff' }
}, () => {});
"

openclaw message send \
  --channel openclaw-weixin \
  --account "1c4f88dcb914-im-bot" \
  --target "$OWNER_PEER" \
  --media "$QR_FILE" \
  --message "子系统 $DISPLAY_NAME 二维码 👆 让朋友扫码绑定" 2>&1 || true

echo "✅ 二维码已发送"

# ──── 阶段 6：后台监听扫码结果 ────
echo ""
echo "⏳ 后台等待朋友扫码（登录进程 PID: $LOGIN_PID）..."

# 写入等待信息
echo "$LOGIN_PID" > "$WORKSPACE/tenants/$TENANT_ID-login.pid"

# 后台监听：扫码成功后更新白名单
(
  for i in $(seq 1 120); do
    sleep 5
    if ! kill -0 "$LOGIN_PID" 2>/dev/null; then
      # 登录进程结束 = 扫码成功
      if [ -f "$ALLOW_FROM_FILE" ]; then
        node -e "
          const fs = require('fs');
          // 朋友的 peer ID 需要等第一条消息才能知道
          // 这里只确保主人在白名单中
          const list = JSON.parse(fs.readFileSync('$ALLOW_FROM_FILE', 'utf8'));
          if (!list.includes('$OWNER_PEER')) {
            list.push('$OWNER_PEER');
            fs.writeFileSync('$ALLOW_FROM_FILE', JSON.stringify(list, null, 2));
          }
        "
      fi
      rm -f "$WORKSPACE/tenants/$TENANT_ID-login.pid"
      rm -f "$LOGIN_LOG"
      break
    fi
  done
) &
DISOWN_PID=$!

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 $TENANT_ID ($DISPLAY_NAME) 创建完成！"
echo ""
echo "  账号:   $NEW_ACCOUNT"
echo "  绑定:   $NEW_ACCOUNT → $TENANT_ID"
echo "  二维码: 已发送"
echo ""
echo "✅ 绑定已在朋友扫码前生效"
echo "   朋友扫码后消息直接进入 $TENANT_ID"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
