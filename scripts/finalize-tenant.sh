#!/bin/sh
# 朋友扫码后，完成 tenant 绑定（阶段 3：写路由 + 白名单监听）
# 用法: sh scripts/finalize-tenant.sh <tenantId>

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
WX_ACCOUNTS_FILE="$HOME/.openclaw/openclaw-weixin/accounts.json"
ALLOW_FROM_FILE="$HOME/.openclaw/credentials/openclaw-weixin-allowFrom.json"
AGENTS_DIR="$HOME/.openclaw/agents"
OWNER_ACCOUNT="${OWNER_ACCOUNT:-1c4f88dcb914-im-bot}"
TENANT_ID="${1:-}"

if [ -z "$TENANT_ID" ]; then
  echo "用法: sh scripts/finalize-tenant.sh <tenantId>"
  echo "例: sh scripts/finalize-tenant.sh friend-001"
  exit 1
fi

PENDING_FILE="$WORKSPACE/tenants/${TENANT_ID}-pending.json"
if [ ! -f "$PENDING_FILE" ]; then
  echo "⚠️  找不到 $PENDING_FILE"
  echo "请先运行 sh scripts/generate-tenant-qr.sh $TENANT_ID。"
  exit 1
fi

PREV=$(node -e "
  const fs = require('fs');
  const pending = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
  console.log(JSON.stringify(pending.existingAccounts || []));
" "$PENDING_FILE")
CURRENT=$(cat "$WX_ACCOUNTS_FILE" 2>/dev/null || echo "[]")

NEW_ACCOUNT=$(node -e "
  const prev = JSON.parse(process.argv[1]);
  const cur = JSON.parse(process.argv[2]);
  const newOnes = cur.filter((id) => !prev.includes(id));
  if (newOnes.length === 0) {
    console.log('');
  } else {
    if (newOnes.length > 1) console.error('⚠️  多个新账号: ' + newOnes.join(', ') + '，使用第一个');
    console.log(newOnes[0]);
  }
" "$PREV" "$CURRENT")

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

openclaw agents unbind --agent "$TENANT_ID" --all >/dev/null 2>&1 || true
if ! openclaw agents bind --agent "$TENANT_ID" --bind "openclaw-weixin:$NEW_ACCOUNT" >/dev/null; then
  echo "❌ 路由绑定失败"
  echo "   恢复建议: openclaw agents bind --agent $TENANT_ID --bind openclaw-weixin:$NEW_ACCOUNT"
  exit 1
fi
echo "✅ 路由绑定已更新: $NEW_ACCOUNT → $TENANT_ID"

node -e "
  const fs = require('fs');
  const [registryPath, tenantId, accountId] = process.argv.slice(1);
  const reg = JSON.parse(fs.readFileSync(registryPath, 'utf8'));
  if (reg.tenants?.[tenantId]) {
    reg.tenants[tenantId].accountId = accountId;
    reg.tenants[tenantId].bound = true;
    reg.tenants[tenantId].boundAt = new Date().toISOString();
    fs.writeFileSync(registryPath, JSON.stringify(reg, null, 2));
  }
" "$REGISTRY" "$TENANT_ID" "$NEW_ACCOUNT"
echo "✅ 注册表已更新"

OWNER_PEER=$(node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
  console.log(reg.ownerPeer || '');
" "$REGISTRY" 2>/dev/null)
LOGIN_PID=$(node -e "
  const fs = require('fs');
  const pending = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
  console.log(pending.loginPid || '');
" "$PENDING_FILE" 2>/dev/null)

if [ -n "$LOGIN_PID" ]; then
  kill "$LOGIN_PID" 2>/dev/null || true
fi

rm -f "$PENDING_FILE"

echo ""
if ! sh "$WORKSPACE/scripts/gateway-reload.sh"; then
  echo "⚠️  热重载未完全确认成功，请手动验证路由。"
fi

(
  AGENT_SESSIONS="$AGENTS_DIR/$TENANT_ID/sessions"
  FOUND="false"

  for i in $(seq 1 720); do
    sleep 5

    FRIEND_PEER=$(node -e "
      const fs = require('fs');
      const dir = process.argv[1];
      try {
        if (!fs.existsSync(dir)) process.exit(0);
        const files = fs.readdirSync(dir).filter((file) => file.endsWith('.json') && !file.startsWith('.'));
        for (const file of files) {
          try {
            const session = JSON.parse(fs.readFileSync(dir + '/' + file, 'utf8'));
            if (session.origin && session.origin.from) {
              console.log(session.origin.from);
              process.exit(0);
            }
          } catch (error) {}
        }
      } catch (error) {}
    " "$AGENT_SESSIONS" 2>/dev/null)

    if [ -n "$FRIEND_PEER" ]; then
      if [ ! -f "$ALLOW_FROM_FILE" ]; then
        mkdir -p "$(dirname "$ALLOW_FROM_FILE")"
        echo '[]' > "$ALLOW_FROM_FILE"
      fi

      WAS_ADDED=$(node -e "
        const fs = require('fs');
        const [allowFile, peerId] = process.argv.slice(1);
        let list = JSON.parse(fs.readFileSync(allowFile, 'utf8'));
        if (!list.includes(peerId)) {
          list.push(peerId);
          fs.writeFileSync(allowFile, JSON.stringify(list, null, 2));
          console.log('yes');
        } else {
          console.log('no');
        }
      " "$ALLOW_FROM_FILE" "$FRIEND_PEER" 2>/dev/null)

      if [ "$WAS_ADDED" = "yes" ]; then
        node -e "process.kill(1, 'SIGUSR1')" 2>/dev/null || true
        sleep 2
        if [ -n "$OWNER_PEER" ]; then
          openclaw message send \
            --channel openclaw-weixin \
            --account "$OWNER_ACCOUNT" \
            --target "$OWNER_PEER" \
            --message "🎉 $TENANT_ID 绑定成功！朋友已加入白名单，可以开始聊天了。" 2>&1 || true
        fi
      fi

      FOUND="true"
      break
    fi
  done

  if [ "$FOUND" != "true" ] && [ -n "$OWNER_PEER" ]; then
    openclaw message send \
      --channel openclaw-weixin \
      --account "$OWNER_ACCOUNT" \
      --target "$OWNER_PEER" \
      --message "⏰ $TENANT_ID 绑定后 1 小时内未检测到首条消息；如需排查，运行: sh scripts/healthcheck-tenant.sh $TENANT_ID" 2>&1 || true
  fi
) >/dev/null 2>&1 &

echo "✅ 已启动后台白名单监听"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎉 $TENANT_ID 绑定完成！"
echo ""
echo "  账号:   $NEW_ACCOUNT"
echo "  Agent:  $TENANT_ID"
echo ""
echo "朋友现在可以发消息了，会自动进入 $TENANT_ID 系统。"
echo "首条消息后会自动加入白名单。"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
