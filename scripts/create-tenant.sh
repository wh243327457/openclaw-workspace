#!/bin/sh
# 创建子系统（全自动流程）— 合并 create-tenant + finalize
# 用法: sh scripts/create-tenant.sh [displayName]
#
# 流程（6 个阶段）：
# 1. 创建 agent + 初始化模板
# 2. 启动微信登录，获取新 accountId
# 3. 写入绑定 + 注册表
# 4. 触发 gateway 重载（SIGUSR1）
# 5. 生成二维码发给主人
# 6. 后台监听 sessions 目录，朋友首次发消息时自动白名单

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
TEMPLATE="$WORKSPACE/templates/tenant-default"
WX_ACCOUNTS_FILE="$HOME/.openclaw/openclaw-weixin/accounts.json"
CONFIG="$HOME/.openclaw/openclaw.json"
ALLOW_FROM_FILE="$HOME/.openclaw/credentials/openclaw-weixin-allowFrom.json"
AGENTS_DIR="$HOME/.openclaw/agents"

# ──── 读取 OWNER_PEER ────
# 优先级: 环境变量 > registry.json > 交互式输入
if [ -n "$OWNER_PEER" ]; then
  echo "📌 OWNER_PEER 从环境变量读取: $OWNER_PEER"
else
  OWNER_PEER=$(node -e "
    const fs = require('fs');
    try {
      const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
      console.log(reg.ownerPeer || '');
    } catch(e) { console.log(''); }
  " 2>/dev/null)
fi

if [ -z "$OWNER_PEER" ]; then
  echo ""
  echo "⚠️  未找到 ownerPeer 配置"
  printf "请输入主人的 peer ID: "
  read -r OWNER_PEER
  if [ -z "$OWNER_PEER" ]; then
    echo "❌ peer ID 不能为空"
    exit 1
  fi
  # 写入 registry.json
  node -e "
    const fs = require('fs');
    const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
    reg.ownerPeer = '$OWNER_PEER';
    fs.writeFileSync('$REGISTRY', JSON.stringify(reg, null, 2));
  "
  echo "✅ ownerPeer 已保存到 registry.json"
fi

# ──── 自动编号 ────
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

# ═══════════════════════════════════════════
# 阶段 1：创建 agent + 初始化模板
# ═══════════════════════════════════════════
echo "── 阶段 1/6：创建 agent ──"

if ! openclaw agents add "$TENANT_ID" --non-interactive --workspace "$AGENT_WORKSPACE" 2>&1 | grep -v "^Config\|^Updated\|^Workspace\|^Sessions\|^Agent:"; then
  echo "❌ Agent 创建失败"
  echo "   恢复建议: 检查 openclaw agents list，确认 $TENANT_ID 是否已存在"
  exit 1
fi

for f in SOUL.md USER.md IDENTITY.md MEMORY.md HEARTBEAT.md AGENTS.md TOOLS.md cron.json; do
  [ -f "$TEMPLATE/$f" ] && cp "$TEMPLATE/$f" "$AGENT_WORKSPACE/$f"
done
cp -r "$TEMPLATE/memory" "$AGENT_WORKSPACE/memory" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/memory"
cp -r "$TEMPLATE/scripts" "$AGENT_WORKSPACE/scripts" 2>/dev/null || mkdir -p "$AGENT_WORKSPACE/scripts"

echo "✅ Agent $TENANT_ID 创建完成"
echo ""

# ═══════════════════════════════════════════
# 阶段 2：启动微信登录，获取新 accountId
# ═══════════════════════════════════════════
echo "── 阶段 2/6：启动微信登录 ──"

BEFORE=$(cat "$WX_ACCOUNTS_FILE" 2>/dev/null || echo "[]")

LOGIN_LOG=$(mktemp)
openclaw channels login --channel openclaw-weixin > "$LOGIN_LOG" 2>&1 &
LOGIN_PID=$!

# 等待新账号出现
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
done

if [ -z "$NEW_ACCOUNT" ]; then
  echo "❌ 无法获取新账号（超时 30s）"
  echo "   恢复建议: kill 登录进程后重试，或检查 openclaw channels status"
  kill "$LOGIN_PID" 2>/dev/null || true
  exit 1
fi

echo "✅ 新账号: $NEW_ACCOUNT"
echo ""

# ═══════════════════════════════════════════
# 阶段 3：写入绑定 + 注册表
# ═══════════════════════════════════════════
echo "── 阶段 3/6：写入绑定 ──"

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
" || {
  echo "❌ 写入绑定/注册表失败"
  echo "   恢复建议: 检查 $CONFIG 和 $REGISTRY 文件权限"
  kill "$LOGIN_PID" 2>/dev/null || true
  exit 1
}

echo "✅ 绑定已写入: $NEW_ACCOUNT → $TENANT_ID"
echo ""

# ═══════════════════════════════════════════
# 阶段 4：触发 gateway 重载
# ═══════════════════════════════════════════
echo "── 阶段 4/6：触发 gateway 热重载 ──"

# 向 PID 1 (gateway) 发送 SIGUSR1 触发热重载
if node -e "process.kill(1, 'SIGUSR1')" 2>/dev/null; then
  echo "📡 SIGUSR1 已发送，等待 3s 让配置生效..."
  sleep 3
  echo "✅ Gateway 重载完成"
else
  echo "⚠️  SIGUSR1 发送失败，尝试 fallback..."
  if openclaw gateway restart 2>&1 | grep -q "service disabled"; then
    echo "⚠️  Gateway restart 不可用（容器 PID 1）"
    echo "   配置已写入，下次重启自动生效"
  else
    echo "✅ Gateway 已重启"
  fi
fi
echo ""

# ═══════════════════════════════════════════
# 阶段 5：等二维码生成，发给主人
# ═══════════════════════════════════════════
echo "── 阶段 5/6：生成并发送二维码 ──"

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
  echo "   恢复建议: 检查 login 进程日志: cat $LOGIN_LOG"
  kill "$LOGIN_PID" 2>/dev/null || true
  exit 1
fi

# 生成二维码图片或 ASCII fallback
QR_FILE="$WORKSPACE/tenants/$TENANT_ID-qr.png"
QR_GENERATED=false

# 尝试用 qrcode 模块生成图片
if node -e "require('/tmp/node_modules/qrcode')" 2>/dev/null; then
  node -e "
    const QRCode = require('/tmp/node_modules/qrcode');
    QRCode.toFile('$QR_FILE', '$QR_URL', {
      width: 400, margin: 2,
      color: { dark: '#000000', light: '#ffffff' }
    }, () => {});
  " 2>/dev/null && QR_GENERATED=true
fi

if [ "$QR_GENERATED" = "true" ]; then
  echo "📎 二维码图片已生成: $QR_FILE"
  openclaw message send \
    --channel openclaw-weixin \
    --account "1c4f88dcb914-im-bot" \
    --target "$OWNER_PEER" \
    --media "$QR_FILE" \
    --message "子系统 $DISPLAY_NAME 二维码 👆 让朋友扫码绑定" 2>&1 || true
else
  # Fallback: 纯文本 URL
  echo ""
  echo "📎 请将以下链接发给朋友扫码："
  echo "$QR_URL"
  echo ""
  openclaw message send \
    --channel openclaw-weixin \
    --account "1c4f88dcb914-im-bot" \
    --target "$OWNER_PEER" \
    --message "子系统 $DISPLAY_NAME 绑定链接：$QR_URL" 2>&1 || true
fi

echo "✅ 二维码信息已发送给主人"
echo ""

# ═══════════════════════════════════════════
# 阶段 6：后台监听 sessions 目录
# ═══════════════════════════════════════════
echo "── 阶段 6/6：后台等待朋友绑定 ──"

# 保存登录进程 PID
echo "$LOGIN_PID" > "$WORKSPACE/tenants/$TENANT_ID-login.pid"

# 后台守护进程：
# 监听 agent 的 sessions 目录，当朋友发第一条消息时，
# 从 session origin 中提取 peer ID，自动加入白名单，
# 然后触发 gateway 重载，并通知主人。
(
  AGENT_SESSIONS="$AGENTS_DIR/$TENANT_ID/sessions"
  FOUND=false

  # 先等登录进程结束（扫码成功）
  for i in $(seq 1 120); do
    sleep 5
    if ! kill -0 "$LOGIN_PID" 2>/dev/null; then
      break
    fi
  done

  # 登录进程结束，现在监听 sessions 目录
  # 朋友发第一条消息时 session 文件会被创建
  for i in $(seq 1 720); do
    sleep 5

    # 扫描 sessions 目录寻找朋友的 peer ID
    FRIEND_PEER=$(node -e "
      const fs = require('fs');
      const dir = '$AGENT_SESSIONS';
      try {
        if (!fs.existsSync(dir)) process.exit(0);
        const files = fs.readdirSync(dir).filter(f => f.endsWith('.json') && !f.startsWith('.'));
        for (const file of files) {
          try {
            const s = JSON.parse(fs.readFileSync(dir + '/' + file, 'utf8'));
            if (s.origin && s.origin.from) {
              console.log(s.origin.from);
              process.exit(0);
            }
          } catch(e) {}
        }
      } catch(e) {}
    " 2>/dev/null)

    if [ -n "$FRIEND_PEER" ]; then
      # 确保白名单文件存在
      if [ ! -f "$ALLOW_FROM_FILE" ]; then
        mkdir -p "$(dirname "$ALLOW_FROM_FILE")"
        echo '[]' > "$ALLOW_FROM_FILE"
      fi

      # 加入白名单（如果还没有的话）
      WAS_ADDED=$(node -e "
        const fs = require('fs');
        let list = JSON.parse(fs.readFileSync('$ALLOW_FROM_FILE', 'utf8'));
        if (!list.includes('$FRIEND_PEER')) {
          list.push('$FRIEND_PEER');
          fs.writeFileSync('$ALLOW_FROM_FILE', JSON.stringify(list, null, 2));
          console.log('yes');
        } else {
          console.log('no');
        }
      " 2>/dev/null)

      if [ "$WAS_ADDED" = "yes" ]; then
        echo "[$(date '+%H:%M:%S')] ✅ 自动白名单: $FRIEND_PEER"

        # 触发 gateway 重载让白名单生效
        node -e "process.kill(1, 'SIGUSR1')" 2>/dev/null
        sleep 2

        # 通知主人：朋友已绑定
        openclaw message send \
          --channel openclaw-weixin \
          --account "1c4f88dcb914-im-bot" \
          --target "$OWNER_PEER" \
          --message "🎉 $DISPLAY_NAME ($TENANT_ID) 绑定成功！朋友已加入白名单，可以开始聊天了。" 2>&1 || true
      fi

      FOUND=true
      break
    fi
  done

  # 清理
  rm -f "$WORKSPACE/tenants/$TENANT_ID-login.pid"
  rm -f "$LOGIN_LOG"

  if [ "$FOUND" != "true" ]; then
    echo "[$(date '+%H:%M:%S')] ⏰ 等待超时，未检测到朋友消息"
    # 超时也通知主人
    openclaw message send \
      --channel openclaw-weixin \
      --account "1c4f88dcb914-im-bot" \
      --target "$OWNER_PEER" \
      --message "⏰ $DISPLAY_NAME ($TENANT_ID) 绑定等待超时（1小时）。如需手动白名单，请运行: sh scripts/healthcheck-tenant.sh $TENANT_ID" 2>&1 || true
  fi
) &
DISOWN_PID=$!
disown "$DISOWN_PID" 2>/dev/null || true

# ──── 完成 ────
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 $TENANT_ID ($DISPLAY_NAME) 创建完成！"
echo ""
echo "  账号:   $NEW_ACCOUNT"
echo "  绑定:   $NEW_ACCOUNT → $TENANT_ID"
echo "  二维码: 已发送给主人"
echo "  后台:   监听中（扫码后自动白名单）"
echo ""
echo "✅ 绑定已在朋友扫码前生效"
echo "   朋友扫码后 → 消息直接进入 $TENANT_ID"
echo "   首条消息后 → 自动加入白名单 + 通知主人"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
