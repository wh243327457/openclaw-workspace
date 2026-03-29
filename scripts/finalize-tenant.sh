#!/bin/sh
# 朋友扫码后，自动完成 tenant 绑定
# 用法: sh scripts/finalize-tenant.sh [tenantId]
#
# 自动完成：
# 1. 检测新增的微信账号 ID
# 2. 更新 openclaw.json 路由绑定
# 3. 更新注册表
# 4. 重启 gateway

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
WX_ACCOUNTS_FILE="$HOME/.openclaw/openclaw-weixin/accounts.json"
CONFIG="$HOME/.openclaw/openclaw.json"
TENANT_ID="${1:-}"

if [ -z "$TENANT_ID" ]; then
  echo "用法: sh scripts/finalize-tenant.sh <tenantId>"
  echo "例: sh scripts/finalize-tenant.sh friend-001"
  exit 1
fi

PENDING_FILE="$WORKSPACE/tenants/${TENANT_ID}-pending.json"
if [ ! -f "$PENDING_FILE" ]; then
  echo "⚠️  找不到 $PENDING_FILE"
  echo "该 tenant 可能已经完成绑定，或者文件被清理了。"
  exit 1
fi

# 读取之前记录的账号列表
PREV=$(node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync('$PENDING_FILE','utf8')).existingAccounts))")

# 读取当前账号列表
CURRENT=$(node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync('$WX_ACCOUNTS_FILE','utf8'))))")

# 找出新增的账号
NEW_ACCOUNT=$(node -e "
  const prev = $PREV;
  const cur = $CURRENT;
  const newOnes = cur.filter(id => !prev.includes(id));
  if (newOnes.length === 0) {
    console.log('');
  } else {
    if (newOnes.length > 1) console.error('⚠️  多个新账号: ' + newOnes.join(', ') + '，使用第一个');
    console.log(newOnes[0]);
  }
")

if [ -z "$NEW_ACCOUNT" ]; then
  echo "❌ 未检测到新增的微信账号。"
  echo ""
  echo "可能原因："
  echo "  - 朋友还没扫码"
  echo "  - 朋友之前已经绑定过这个机器人"
  echo ""
  echo "当前账号列表: $CURRENT"
  echo "之前的账号: $PREV"
  exit 1
fi

echo "✅ 检测到新账号: $NEW_ACCOUNT"

# 更新绑定配置
node -e "
  const fs = require('fs');
  const config = JSON.parse(fs.readFileSync('$CONFIG', 'utf8'));
  if (!config.bindings) config.bindings = [];
  
  // 移除该 tenant 的旧绑定（如果存在）
  config.bindings = config.bindings.filter(b => b.agentId !== '$TENANT_ID');
  
  // 添加新绑定
  config.bindings.push({
    agentId: '$TENANT_ID',
    match: {
      channel: 'openclaw-weixin',
      accountId: '$NEW_ACCOUNT'
    }
  });
  
  fs.writeFileSync('$CONFIG', JSON.stringify(config, null, 2));
  console.log('✅ 路由绑定已更新: $NEW_ACCOUNT → $TENANT_ID');
"

# 更新注册表
node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  if (reg.tenants['$TENANT_ID']) {
    reg.tenants['$TENANT_ID'].accountId = '$NEW_ACCOUNT';
    reg.tenants['$TENANT_ID'].bound = true;
    fs.writeFileSync('$REGISTRY', JSON.stringify(reg, null, 2));
    console.log('✅ 注册表已更新');
  }
"

# 获取朋友的 peer ID 并加入白名单
PEER_ID=$(node -e "
  const fs = require('fs');
  const sessionsFile = '$HOME/.openclaw/agents/$TENANT_ID/sessions/sessions.json';
  if (fs.existsSync(sessionsFile)) {
    const sessions = JSON.parse(fs.readFileSync(sessionsFile, 'utf8'));
    for (const [k, v] of Object.entries(sessions)) {
      if (v.origin?.from) { console.log(v.origin.from); break; }
    }
  }
")
ALLOW_FROM_FILE="$HOME/.openclaw/credentials/openclaw-weixin-allowFrom.json"
if [ -n "$PEER_ID" ] && [ -f "$ALLOW_FROM_FILE" ]; then
  node -e "
    const fs = require('fs');
    const list = JSON.parse(fs.readFileSync('$ALLOW_FROM_FILE', 'utf8'));
    if (!list.includes('$PEER_ID')) {
      list.push('$PEER_ID');
      fs.writeFileSync('$ALLOW_FROM_FILE', JSON.stringify(list, null, 2));
      console.log('✅ 已加入白名单: $PEER_ID');
    } else {
      console.log('✅ 已在白名单中');
    }
  "
elif [ -n "$PEER_ID" ]; then
  echo "[$PEER_ID]" > "$ALLOW_FROM_FILE"
  echo "✅ 白名单文件已创建"
fi

# 清理临时文件
rm -f "$PENDING_FILE"
rm -f "$WORKSPACE/tenants/${TENANT_ID}-login.pid"

# 重启 gateway
echo ""
echo "🔄 重启 gateway..."
if openclaw gateway restart 2>&1 | grep -q "service disabled"; then
  echo "⚠️  gateway 是容器 PID 1，无法通过 CLI 重启。"
  echo "请手动重启容器，或者让朋友发一条消息测试（配置可能已自动加载）。"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 $TENANT_ID 绑定完成！"
echo ""
echo "  账号:   $NEW_ACCOUNT"
echo "  Agent:  $TENANT_ID"
echo ""
echo "朋友现在可以发消息了，会自动进入 $TENANT_ID 系统。"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
