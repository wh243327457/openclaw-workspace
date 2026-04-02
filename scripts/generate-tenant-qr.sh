#!/bin/sh
# 生成 tenant 绑定二维码（阶段 2：启动登录 + 出码）
# 用法: sh scripts/generate-tenant-qr.sh <tenantId>

set -e

WORKSPACE="${WORKSPACE:-/home/node/.openclaw/workspace}"
REGISTRY="${REGISTRY:-$WORKSPACE/tenants/registry.json}"
WX_ACCOUNTS_FILE="${WX_ACCOUNTS_FILE:-$HOME/.openclaw/openclaw-weixin/accounts.json}"
OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
NOTIFY_OWNER="${NOTIFY_OWNER:-true}"
QR_RENDERER="${QR_RENDERER:-$WORKSPACE/scripts/render-weixin-login-qr.js}"
TENANT_ID="${1:-}"
PENDING_FILE="$WORKSPACE/tenants/${TENANT_ID}-pending.json"
LOGIN_LOG="$WORKSPACE/tenants/${TENANT_ID}-login.log"
WATCH_LOG="$WORKSPACE/tenants/${TENANT_ID}-watch.log"
WATCH_PID_FILE="$WORKSPACE/tenants/${TENANT_ID}-watch.pid"
OWNER_ACCOUNT="${OWNER_ACCOUNT:-1c4f88dcb914-im-bot}"

if [ -z "$TENANT_ID" ]; then
  echo "用法: sh scripts/generate-tenant-qr.sh <tenantId>"
  echo "例: sh scripts/generate-tenant-qr.sh friend-001"
  exit 1
fi

mkdir -p "$WORKSPACE/tenants"

if [ -f "$PENDING_FILE" ]; then
  echo "⚠️  已存在待完成的二维码流程: $PENDING_FILE"
  echo "请先完成 sh scripts/finalize-tenant.sh $TENANT_ID --account <accountId>"
  echo "若确认上次流程已失效，可先备份后重试: mv $PENDING_FILE ${PENDING_FILE%.json}-stale-\$(date +%s).json"
  exit 1
fi

if [ -f "$WATCH_PID_FILE" ]; then
  OLD_WATCH_PID=$(cat "$WATCH_PID_FILE" 2>/dev/null || true)
  if [ -n "$OLD_WATCH_PID" ] && kill -0 "$OLD_WATCH_PID" 2>/dev/null; then
    echo "⚠️  已存在后台绑定监听进程: $OLD_WATCH_PID"
    echo "请先完成当前扫码流程，或清理 $WATCH_PID_FILE 后重试。"
    exit 1
  fi
  rm -f "$WATCH_PID_FILE"
fi

TENANT_INFO=$(node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync(process.argv[1], 'utf8'));
  const tenant = reg.tenants?.[process.argv[2]];
  if (!tenant) process.exit(1);
  console.log(JSON.stringify({
    displayName: tenant.displayName || process.argv[2],
    ownerPeer: reg.ownerPeer || ''
  }));
" "$REGISTRY" "$TENANT_ID" 2>/dev/null) || {
  echo "❌ Tenant 不存在: $TENANT_ID"
  exit 1
}

DISPLAY_NAME=$(node -e "console.log(JSON.parse(process.argv[1]).displayName || '')" "$TENANT_INFO")
OWNER_PEER=$(node -e "console.log(JSON.parse(process.argv[1]).ownerPeer || '')" "$TENANT_INFO")
BEFORE=$(cat "$WX_ACCOUNTS_FILE" 2>/dev/null || echo "[]")

update_pending() {
  node -e "
    const fs = require('fs');
    const filePath = process.argv[1];
    const patch = JSON.parse(process.argv[2]);
    const current = fs.existsSync(filePath)
      ? JSON.parse(fs.readFileSync(filePath, 'utf8'))
      : {};
    fs.writeFileSync(filePath, JSON.stringify({ ...current, ...patch }, null, 2));
  " "$PENDING_FILE" "$1"
}

send_owner_notice() {
  MESSAGE_BODY="$1"
  MEDIA_PATH="$2"

  if [ -z "$OWNER_PEER" ] || [ "$NOTIFY_OWNER" != "true" ]; then
    return 0
  fi

  if [ -n "$MEDIA_PATH" ] && [ -f "$MEDIA_PATH" ]; then
    $OPENCLAW_BIN message send \
      --channel openclaw-weixin \
      --account "$OWNER_ACCOUNT" \
      --target "$OWNER_PEER" \
      --media "$MEDIA_PATH" \
      --message "$MESSAGE_BODY" 2>&1 || true
  else
    $OPENCLAW_BIN message send \
      --channel openclaw-weixin \
      --account "$OWNER_ACCOUNT" \
      --target "$OWNER_PEER" \
      --message "$MESSAGE_BODY" 2>&1 || true
  fi
}

echo "── 阶段 2/3：生成二维码 ──"
echo "⏳ 启动微信登录..."

: > "$LOGIN_LOG"
$OPENCLAW_BIN channels login --channel openclaw-weixin > "$LOGIN_LOG" 2>&1 &
LOGIN_PID=$!

QR_URL=""
QR_FILE="$WORKSPACE/tenants/$TENANT_ID-qr.png"
QR_PBM_FILE="$WORKSPACE/tenants/$TENANT_ID-qr.pbm"
QR_GENERATED="false"

for i in $(seq 1 30); do
  sleep 1
  if [ -z "$QR_URL" ] && grep -q "qrcode=" "$LOGIN_LOG" 2>/dev/null; then
    QR_URL=$(node -e "
      const fs = require('fs');
      const text = fs.readFileSync(process.argv[1], 'utf8');
      const matches = [...text.matchAll(/https:\/\/[^\s]*qrcode=[^\s]*/g)].map((entry) => entry[0]);
      console.log(matches[matches.length - 1] || '');
    " "$LOGIN_LOG" 2>/dev/null)
  fi

  if [ "$QR_GENERATED" != "true" ] && node "$QR_RENDERER" \
    --input "$LOGIN_LOG" \
    --pbm "$QR_PBM_FILE" \
    --png "$QR_FILE" >/dev/null 2>&1; then
    QR_GENERATED="true"
  fi

  if [ "$QR_GENERATED" = "true" ] || [ -n "$QR_URL" ]; then
    break
  fi

  if ! kill -0 "$LOGIN_PID" 2>/dev/null; then
    break
  fi
done

if [ "$QR_GENERATED" != "true" ] && [ -z "$QR_URL" ]; then
  echo "❌ 二维码生成失败"
  echo "   排查日志: cat $LOGIN_LOG"
  kill "$LOGIN_PID" 2>/dev/null || true
  exit 1
fi

node -e "
  const fs = require('fs');
  const [filePath, tenantId, displayName, existingAccounts, loginPid, loginLog, qrFile, qrUrl] = process.argv.slice(1);
  fs.writeFileSync(filePath, JSON.stringify({
    tenantId,
    displayName,
    existingAccounts: JSON.parse(existingAccounts),
    loginPid: Number(loginPid),
    loginLog,
    qrFile,
    qrUrl,
    status: 'awaiting_scan',
    createdAt: new Date().toISOString()
  }, null, 2));
" "$PENDING_FILE" "$TENANT_ID" "$DISPLAY_NAME" "$BEFORE" "$LOGIN_PID" "$LOGIN_LOG" "$QR_FILE" "$QR_URL"

if [ "$QR_GENERATED" = "true" ]; then
  send_owner_notice "子系统 $DISPLAY_NAME 二维码 👆 让朋友扫码绑定" "$QR_FILE"
elif [ -n "$QR_URL" ]; then
  send_owner_notice "子系统 $DISPLAY_NAME 绑定链接：$QR_URL" ""
fi

(
  trap 'rm -f "$WATCH_PID_FILE"' EXIT
  LOGIN_DEAD_STREAK=0

  for i in $(seq 1 360); do
    sleep 5
    [ -f "$PENDING_FILE" ] || exit 0

    CURRENT=$(cat "$WX_ACCOUNTS_FILE" 2>/dev/null || echo "[]")
    DIFF_JSON=$(node -e "
      const prev = JSON.parse(process.argv[1]);
      const cur = JSON.parse(process.argv[2]);
      const diff = cur.filter((id) => !prev.includes(id));
      console.log(JSON.stringify(diff));
    " "$BEFORE" "$CURRENT" 2>/dev/null)

    DIFF_COUNT=$(node -e "console.log(JSON.parse(process.argv[1]).length)" "$DIFF_JSON" 2>/dev/null || echo "0")

    if [ "$DIFF_COUNT" -eq 1 ]; then
      NEW_ACCOUNT=$(node -e "console.log(JSON.parse(process.argv[1])[0] || '')" "$DIFF_JSON" 2>/dev/null)
      sh "$WORKSPACE/scripts/finalize-tenant.sh" "$TENANT_ID" --account "$NEW_ACCOUNT" >> "$WATCH_LOG" 2>&1 || true
      exit 0
    fi

    if [ "$DIFF_COUNT" -gt 1 ]; then
      CANDIDATES=$(node -e "console.log(JSON.parse(process.argv[1]).join(', '))" "$DIFF_JSON" 2>/dev/null)
      update_pending "{\"status\":\"ambiguous-account\",\"candidateAccounts\":$(printf '%s' "$DIFF_JSON")}" >/dev/null 2>&1 || true
      send_owner_notice "⚠️ $TENANT_ID 检测到多个新账号：$CANDIDATES。请手动执行：sh scripts/finalize-tenant.sh $TENANT_ID --account <accountId>" ""
      exit 0
    fi

    if kill -0 "$LOGIN_PID" 2>/dev/null; then
      LOGIN_DEAD_STREAK=0
      continue
    fi

    LOGIN_DEAD_STREAK=$((LOGIN_DEAD_STREAK + 1))
    if [ "$LOGIN_DEAD_STREAK" -ge 3 ]; then
      update_pending "{\"status\":\"qr-expired\"}" >/dev/null 2>&1 || true
      ARCHIVED_PENDING="$WORKSPACE/tenants/${TENANT_ID}-pending-expired-$(date +%s).json"
      mv "$PENDING_FILE" "$ARCHIVED_PENDING" 2>/dev/null || true
      send_owner_notice "⏰ $TENANT_ID 的二维码已失效，重新出码：sh scripts/generate-tenant-qr.sh $TENANT_ID" ""
      exit 0
    fi
  done

  update_pending "{\"status\":\"watch-timeout\"}" >/dev/null 2>&1 || true
  ARCHIVED_PENDING="$WORKSPACE/tenants/${TENANT_ID}-pending-timeout-$(date +%s).json"
  mv "$PENDING_FILE" "$ARCHIVED_PENDING" 2>/dev/null || true
  send_owner_notice "⏰ $TENANT_ID 等待扫码超时，重新出码：sh scripts/generate-tenant-qr.sh $TENANT_ID" ""
) >/dev/null 2>&1 &
WATCH_PID=$!
echo "$WATCH_PID" > "$WATCH_PID_FILE"
update_pending "{\"watchPid\":$WATCH_PID,\"watchLog\":\"$WATCH_LOG\"}" >/dev/null 2>&1

echo "✅ 二维码已生成"
if [ "$QR_GENERATED" = "true" ]; then
  echo "📎 二维码图片: $QR_FILE"
else
  echo "📎 绑定链接: $QR_URL"
fi
if [ -n "$OWNER_PEER" ]; then
  echo "✅ 已发送给主人"
else
  echo "⚠️  未配置 ownerPeer，未自动发送给主人"
fi
echo "✅ 已启动后台绑定监听: $WATCH_PID"
echo ""
echo "朋友扫码后将自动完成绑定，无需手工再运行 finalize。"
echo "手动补救："
echo "  - 已知 accountId：sh scripts/finalize-tenant.sh $TENANT_ID --account <accountId>"
echo "  - 二维码失效重来：sh scripts/generate-tenant-qr.sh $TENANT_ID"
