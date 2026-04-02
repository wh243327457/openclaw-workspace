#!/bin/sh
# 生成 tenant 绑定二维码（阶段 2：启动登录 + 出码）
# 用法: sh scripts/generate-tenant-qr.sh <tenantId>

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
WX_ACCOUNTS_FILE="$HOME/.openclaw/openclaw-weixin/accounts.json"
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
  echo "请先完成 sh scripts/finalize-tenant.sh $TENANT_ID，或手动清理 pending 文件后重试。"
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

echo "── 阶段 2/3：生成二维码 ──"
echo "⏳ 启动微信登录..."

: > "$LOGIN_LOG"
openclaw channels login --channel openclaw-weixin > "$LOGIN_LOG" 2>&1 &
LOGIN_PID=$!

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
  echo "   排查日志: cat $LOGIN_LOG"
  kill "$LOGIN_PID" 2>/dev/null || true
  exit 1
fi

node -e "
  const fs = require('fs');
  const [filePath, tenantId, displayName, existingAccounts, loginPid, loginLog, qrUrl] = process.argv.slice(1);
  fs.writeFileSync(filePath, JSON.stringify({
    tenantId,
    displayName,
    existingAccounts: JSON.parse(existingAccounts),
    loginPid: Number(loginPid),
    loginLog,
    qrUrl,
    createdAt: new Date().toISOString()
  }, null, 2));
" "$PENDING_FILE" "$TENANT_ID" "$DISPLAY_NAME" "$BEFORE" "$LOGIN_PID" "$LOGIN_LOG" "$QR_URL"

QR_FILE="$WORKSPACE/tenants/$TENANT_ID-qr.png"
QR_GENERATED="false"

if node -e "require('/tmp/node_modules/qrcode')" 2>/dev/null; then
  node -e "
    const QRCode = require('/tmp/node_modules/qrcode');
    QRCode.toFile(process.argv[1], process.argv[2], {
      width: 400,
      margin: 2,
      color: { dark: '#000000', light: '#ffffff' }
    }, (error) => {
      if (error) process.exit(1);
    });
  " "$QR_FILE" "$QR_URL" 2>/dev/null && QR_GENERATED="true"
fi

if [ -n "$OWNER_PEER" ]; then
  if [ "$QR_GENERATED" = "true" ]; then
    openclaw message send \
      --channel openclaw-weixin \
      --account "$OWNER_ACCOUNT" \
      --target "$OWNER_PEER" \
      --media "$QR_FILE" \
      --message "子系统 $DISPLAY_NAME 二维码 👆 让朋友扫码绑定" 2>&1 || true
  else
    openclaw message send \
      --channel openclaw-weixin \
      --account "$OWNER_ACCOUNT" \
      --target "$OWNER_PEER" \
      --message "子系统 $DISPLAY_NAME 绑定链接：$QR_URL" 2>&1 || true
  fi
fi

(
  for i in $(seq 1 360); do
    sleep 5
    CURRENT=$(cat "$WX_ACCOUNTS_FILE" 2>/dev/null || echo "[]")
    NEW_ACCOUNT=$(node -e "
      const prev = JSON.parse(process.argv[1]);
      const cur = JSON.parse(process.argv[2]);
      const diff = cur.filter((id) => !prev.includes(id));
      console.log(diff[0] || '');
    " "$BEFORE" "$CURRENT" 2>/dev/null)

    if [ -n "$NEW_ACCOUNT" ]; then
      sh "$WORKSPACE/scripts/finalize-tenant.sh" "$TENANT_ID" >> "$WATCH_LOG" 2>&1 || true
      break
    fi
  done

  rm -f "$WATCH_PID_FILE"
) >/dev/null 2>&1 &
WATCH_PID=$!
echo "$WATCH_PID" > "$WATCH_PID_FILE"

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
