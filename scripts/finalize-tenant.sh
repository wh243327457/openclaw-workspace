#!/bin/sh
# 朋友扫码后，完成 tenant 绑定（阶段 3：写路由 + 白名单监听）
# 用法: sh scripts/finalize-tenant.sh <tenantId> [--account <accountId>]

set -e

WORKSPACE="${WORKSPACE:-/home/node/.openclaw/workspace}"
REGISTRY="${REGISTRY:-$WORKSPACE/tenants/registry.json}"
WX_ACCOUNTS_FILE="${WX_ACCOUNTS_FILE:-$HOME/.openclaw/openclaw-weixin/accounts.json}"
ALLOW_FROM_FILE="${ALLOW_FROM_FILE:-$HOME/.openclaw/credentials/openclaw-weixin-allowFrom.json}"
AGENTS_DIR="${AGENTS_DIR:-$HOME/.openclaw/agents}"
OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
NOTIFY_OWNER="${NOTIFY_OWNER:-true}"
OWNER_ACCOUNT="${OWNER_ACCOUNT:-1c4f88dcb914-im-bot}"
TENANT_ID=""
EXPLICIT_ACCOUNT=""

update_registry_tenant() {
  node -e '
    const fs = require("fs");
    const [registryPath, tenantId, patchJson] = process.argv.slice(1);
    const reg = JSON.parse(fs.readFileSync(registryPath, "utf8"));
    if (!reg.tenants?.[tenantId]) process.exit(0);
    const patch = JSON.parse(patchJson);
    reg.tenants[tenantId] = { ...reg.tenants[tenantId], ...patch };
    fs.writeFileSync(registryPath, JSON.stringify(reg, null, 2));
  ' "$REGISTRY" "$TENANT_ID" "$1"
}

update_pending() {
  if [ ! -f "$PENDING_FILE" ]; then
    return 0
  fi

  node -e '
    const fs = require("fs");
    const [filePath, patchJson] = process.argv.slice(1);
    const current = JSON.parse(fs.readFileSync(filePath, "utf8"));
    const patch = JSON.parse(patchJson);
    fs.writeFileSync(filePath, JSON.stringify({ ...current, ...patch }, null, 2));
  ' "$PENDING_FILE" "$1"
}

send_owner_notice() {
  MESSAGE_BODY="$1"
  if [ -z "$OWNER_PEER" ] || [ "$NOTIFY_OWNER" != "true" ]; then
    return 0
  fi

  $OPENCLAW_BIN message send \
    --channel openclaw-weixin \
    --account "$OWNER_ACCOUNT" \
    --target "$OWNER_PEER" \
    --message "$MESSAGE_BODY" >/dev/null 2>&1 || true
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --account)
      if [ -z "$2" ]; then
        echo "用法: sh scripts/finalize-tenant.sh <tenantId> [--account <accountId>]"
        exit 1
      fi
      EXPLICIT_ACCOUNT="$2"
      shift 2
      ;;
    *)
      if [ -z "$TENANT_ID" ]; then
        TENANT_ID="$1"
        shift
      else
        echo "用法: sh scripts/finalize-tenant.sh <tenantId> [--account <accountId>]"
        exit 1
      fi
      ;;
  esac
done

if [ -z "$TENANT_ID" ]; then
  echo "用法: sh scripts/finalize-tenant.sh <tenantId> [--account <accountId>]"
  echo "例: sh scripts/finalize-tenant.sh friend-001 --account 23a4b168c28e-im-bot"
  exit 1
fi

PENDING_FILE="$WORKSPACE/tenants/${TENANT_ID}-pending.json"
WATCH_PID_FILE="$WORKSPACE/tenants/${TENANT_ID}-watch.pid"

if [ ! -f "$PENDING_FILE" ] && [ -z "$EXPLICIT_ACCOUNT" ]; then
  echo "⚠️  找不到 $PENDING_FILE"
  echo "请先运行 sh scripts/generate-tenant-qr.sh $TENANT_ID，或直接指定 --account 手动完成绑定。"
  exit 1
fi

CURRENT=$(cat "$WX_ACCOUNTS_FILE" 2>/dev/null || echo "[]")

if ! node -e '
  const fs = require("fs");
  const reg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  if (!reg.tenants?.[process.argv[2]]) process.exit(1);
' "$REGISTRY" "$TENANT_ID" 2>/dev/null; then
  echo "❌ Tenant 不存在: $TENANT_ID"
  exit 1
fi

update_registry_tenant "{\"status\":\"binding\"}" >/dev/null 2>&1 || true
update_pending "{\"status\":\"binding\"}" >/dev/null 2>&1 || true

if [ -n "$EXPLICIT_ACCOUNT" ]; then
  NEW_ACCOUNT="$EXPLICIT_ACCOUNT"
else
  PREV=$(node -e '
    const fs = require("fs");
    const pending = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
    console.log(JSON.stringify(pending.existingAccounts || []));
  ' "$PENDING_FILE")

  DIFF_JSON=$(node -e '
    const prev = JSON.parse(process.argv[1]);
    const cur = JSON.parse(process.argv[2]);
    const newOnes = cur.filter((id) => !prev.includes(id));
    console.log(JSON.stringify(newOnes));
  ' "$PREV" "$CURRENT")

  DIFF_COUNT=$(node -e 'console.log(JSON.parse(process.argv[1]).length)' "$DIFF_JSON")
  if [ "$DIFF_COUNT" -gt 1 ]; then
    echo "❌ 检测到多个新增微信账号，拒绝自动选择。"
    echo "候选账号: $(node -e 'console.log(JSON.parse(process.argv[1]).join(", "))' "$DIFF_JSON")"
    echo "请手动执行: sh scripts/finalize-tenant.sh $TENANT_ID --account <accountId>"
    update_registry_tenant "{\"status\":\"ambiguous-account\",\"candidateAccounts\":$DIFF_JSON}" >/dev/null 2>&1 || true
    update_pending "{\"status\":\"ambiguous-account\",\"candidateAccounts\":$DIFF_JSON}" >/dev/null 2>&1 || true
    exit 1
  fi

  NEW_ACCOUNT=$(node -e 'console.log(JSON.parse(process.argv[1])[0] || "")' "$DIFF_JSON")
fi

if [ -z "$NEW_ACCOUNT" ]; then
  echo "❌ 未检测到新增的微信账号。"
  echo ""
  echo "可能原因："
  echo "  - 朋友还没扫码"
  echo "  - 朋友之前已经绑定过这个机器人"
  echo ""
  echo "当前账号列表: $CURRENT"
  update_registry_tenant "{\"status\":\"awaiting_scan\"}" >/dev/null 2>&1 || true
  if [ -n "$EXPLICIT_ACCOUNT" ]; then
    echo "手动补救: 确认 accountId 是否正确，再重试 --account。"
  else
    echo "之前的账号: $PREV"
  fi
  exit 1
fi

if ! node -e '
  const current = JSON.parse(process.argv[1]);
  if (!current.includes(process.argv[2])) process.exit(1);
' "$CURRENT" "$NEW_ACCOUNT" 2>/dev/null; then
  echo "❌ accountId 不在当前微信账号列表中: $NEW_ACCOUNT"
  echo "当前账号列表: $CURRENT"
  update_registry_tenant "{\"status\":\"binding-error\",\"accountId\":$(node -e 'console.log(JSON.stringify(process.argv[1]))' "$NEW_ACCOUNT")}" >/dev/null 2>&1 || true
  exit 1
fi

echo "✅ 检测到新账号: $NEW_ACCOUNT"

$OPENCLAW_BIN agents unbind --agent "$TENANT_ID" --all >/dev/null 2>&1 || true
if ! $OPENCLAW_BIN agents bind --agent "$TENANT_ID" --bind "openclaw-weixin:$NEW_ACCOUNT" >/dev/null; then
  echo "❌ 路由绑定失败"
  echo "   恢复建议: openclaw agents bind --agent $TENANT_ID --bind openclaw-weixin:$NEW_ACCOUNT"
  update_registry_tenant "{\"status\":\"binding-error\",\"accountId\":$(node -e 'console.log(JSON.stringify(process.argv[1]))' "$NEW_ACCOUNT")}" >/dev/null 2>&1 || true
  exit 1
fi
echo "✅ 路由绑定已更新: $NEW_ACCOUNT → $TENANT_ID"

node -e '
  const fs = require("fs");
  const [registryPath, tenantId, accountId] = process.argv.slice(1);
  const reg = JSON.parse(fs.readFileSync(registryPath, "utf8"));
  if (reg.tenants?.[tenantId]) {
    reg.tenants[tenantId].accountId = accountId;
    reg.tenants[tenantId].bound = true;
    reg.tenants[tenantId].status = "bound";
    reg.tenants[tenantId].boundAt = new Date().toISOString();
    fs.writeFileSync(registryPath, JSON.stringify(reg, null, 2));
  }
' "$REGISTRY" "$TENANT_ID" "$NEW_ACCOUNT"
echo "✅ 注册表已更新"

OWNER_PEER=$(node -e '
  const fs = require("fs");
  const reg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  console.log(reg.ownerPeer || "");
' "$REGISTRY" 2>/dev/null)
LOGIN_PID=$(node -e '
  const fs = require("fs");
  const file = process.argv[1];
  if (!fs.existsSync(file)) process.exit(0);
  const pending = JSON.parse(fs.readFileSync(file, "utf8"));
  console.log(pending.loginPid || "");
' "$PENDING_FILE" 2>/dev/null)

if [ -n "$LOGIN_PID" ]; then
  kill "$LOGIN_PID" 2>/dev/null || true
fi

echo ""
if ! sh "$WORKSPACE/scripts/gateway-reload.sh"; then
  echo "⚠️  热重载未完全确认成功，请手动验证路由。"
fi

(
  AGENT_SESSIONS="$AGENTS_DIR/$TENANT_ID/sessions"
  FOUND="false"

  for _ in $(seq 1 720); do
    sleep 5

    FRIEND_PEER=$(node -e '
      const fs = require("fs");
      const dir = process.argv[1];
      try {
        if (!fs.existsSync(dir)) process.exit(0);
        const files = fs.readdirSync(dir).filter((file) => file.endsWith(".json") && !file.startsWith("."));
        for (const file of files) {
          try {
            const session = JSON.parse(fs.readFileSync(dir + "/" + file, "utf8"));
            if (session.origin && session.origin.from) {
              console.log(session.origin.from);
              process.exit(0);
            }
          } catch (error) {}
        }
      } catch (error) {}
    ' "$AGENT_SESSIONS" 2>/dev/null)

    if [ -n "$FRIEND_PEER" ]; then
      if [ ! -f "$ALLOW_FROM_FILE" ]; then
        mkdir -p "$(dirname "$ALLOW_FROM_FILE")"
        echo '[]' > "$ALLOW_FROM_FILE"
      fi

      WAS_ADDED=$(node -e '
        const fs = require("fs");
        const [allowFile, peerId] = process.argv.slice(1);
        let list = JSON.parse(fs.readFileSync(allowFile, "utf8"));
        if (!list.includes(peerId)) {
          list.push(peerId);
          fs.writeFileSync(allowFile, JSON.stringify(list, null, 2));
          console.log("yes");
        } else {
          console.log("no");
        }
      ' "$ALLOW_FROM_FILE" "$FRIEND_PEER" 2>/dev/null)

      update_registry_tenant "{\"peerId\":$(node -e 'console.log(JSON.stringify(process.argv[1]))' "$FRIEND_PEER"),\"status\":\"active\",\"allowlisted\":true}" >/dev/null 2>&1 || true

      if [ "$WAS_ADDED" = "yes" ]; then
        node -e 'process.kill(1, "SIGUSR1")' 2>/dev/null || true
        sleep 2
        send_owner_notice "🎉 $TENANT_ID 绑定成功！朋友已加入白名单，可以开始聊天了。"
      fi

      update_pending "{\"status\":\"active\",\"peerId\":$(node -e 'console.log(JSON.stringify(process.argv[1]))' "$FRIEND_PEER")}" >/dev/null 2>&1 || true
      FOUND="true"
      break
    fi
  done

  if [ "$FOUND" != "true" ]; then
    update_registry_tenant "{\"status\":\"bound-awaiting-first-message\"}" >/dev/null 2>&1 || true
    send_owner_notice "⏰ $TENANT_ID 绑定后 1 小时内未检测到首条消息；如需排查，运行: sh scripts/healthcheck-tenant.sh $TENANT_ID"
  fi
) >/dev/null 2>&1 &

rm -f "$WATCH_PID_FILE"
rm -f "$PENDING_FILE"

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
