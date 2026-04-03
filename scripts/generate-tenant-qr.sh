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
MAX_LOGIN_ATTEMPTS="${MAX_LOGIN_ATTEMPTS:-2}"
QR_POLL_SECONDS="${QR_POLL_SECONDS:-30}"
QR_EXTRA_RENDER_SECONDS="${QR_EXTRA_RENDER_SECONDS:-5}"
WATCH_ITERATIONS="${WATCH_ITERATIONS:-360}"
SCRIPT_BIN="${SCRIPT_BIN:-$(command -v script 2>/dev/null || true)}"
STDBUF_BIN="${STDBUF_BIN:-$(command -v stdbuf 2>/dev/null || true)}"

if [ -z "$TENANT_ID" ]; then
  echo "用法: sh scripts/generate-tenant-qr.sh <tenantId>"
  echo "例: sh scripts/generate-tenant-qr.sh friend-001"
  exit 1
fi

mkdir -p "$WORKSPACE/tenants"

pid_is_alive() {
  PID="$1"
  [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null
}

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
  node -e '
    const fs = require("fs");
    const [filePath, patchJson] = process.argv.slice(1);
    const patch = JSON.parse(patchJson);
    const current = fs.existsSync(filePath)
      ? JSON.parse(fs.readFileSync(filePath, "utf8"))
      : {};
    fs.writeFileSync(filePath, JSON.stringify({ ...current, ...patch }, null, 2));
  ' "$PENDING_FILE" "$1"
}

archive_pending() {
  REASON="$1"
  TIMESTAMP="$(date +%s)"
  ARCHIVED_PENDING="$WORKSPACE/tenants/${TENANT_ID}-pending-${REASON}-${TIMESTAMP}.json"
  if [ -f "$PENDING_FILE" ]; then
    update_pending "{\"status\":\"$REASON\",\"archivedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >/dev/null 2>&1 || true
    mv "$PENDING_FILE" "$ARCHIVED_PENDING" 2>/dev/null || true
  fi
}

send_owner_notice() {
  MESSAGE_BODY="$1"
  MEDIA_PATH="$2"
  LAST_NOTICE_STATUS="skipped"

  if [ -z "$OWNER_PEER" ] || [ "$NOTIFY_OWNER" != "true" ]; then
    return 0
  fi

  if [ -n "$MEDIA_PATH" ] && [ -f "$MEDIA_PATH" ]; then
    if $OPENCLAW_BIN message send \
      --channel openclaw-weixin \
      --account "$OWNER_ACCOUNT" \
      --target "$OWNER_PEER" \
      --media "$MEDIA_PATH" \
      --message "$MESSAGE_BODY" >/dev/null 2>&1; then
      LAST_NOTICE_STATUS="sent-with-media"
      return 0
    fi
    LAST_NOTICE_STATUS="send-failed"
    return 1
  fi

  if $OPENCLAW_BIN message send \
    --channel openclaw-weixin \
    --account "$OWNER_ACCOUNT" \
    --target "$OWNER_PEER" \
    --message "$MESSAGE_BODY" >/dev/null 2>&1; then
    LAST_NOTICE_STATUS="sent"
    return 0
  fi

  LAST_NOTICE_STATUS="send-failed"
  return 1
}

extract_qr_url() {
  node -e '
    const fs = require("fs");
    const text = fs.readFileSync(process.argv[1], "utf8");
    const matches = [...text.matchAll(/https:\/\/[^\s]*qrcode=[^\s]*/g)].map((entry) => entry[0]);
    console.log(matches[matches.length - 1] || "");
  ' "$LOGIN_LOG" 2>/dev/null
}

try_render_qr_image() {
  if [ "$QR_GENERATED" = "true" ]; then
    return 0
  fi

  if node "$QR_RENDERER" \
    --input "$LOGIN_LOG" \
    --pbm "$QR_PBM_FILE" \
    --png "$QR_FILE" > /dev/null 2>"$QR_RENDER_LOG" \
    && [ -s "$QR_FILE" ]; then
    QR_GENERATED="true"
    return 0
  fi

  return 1
}

start_login_capture() {
  : > "$LOGIN_LOG"
  : > "$QR_RENDER_LOG"

  if [ -n "$SCRIPT_BIN" ]; then
    "$SCRIPT_BIN" -qefc "$OPENCLAW_BIN channels login --channel openclaw-weixin" "$LOGIN_LOG" >/dev/null 2>&1 &
    LOGIN_PID=$!
    LOGIN_CAPTURE_MODE="pty-script"
    return 0
  fi

  if [ -n "$STDBUF_BIN" ]; then
    "$STDBUF_BIN" -oL -eL "$OPENCLAW_BIN" channels login --channel openclaw-weixin > "$LOGIN_LOG" 2>&1 &
    LOGIN_PID=$!
    LOGIN_CAPTURE_MODE="stdbuf"
    return 0
  fi

  $OPENCLAW_BIN channels login --channel openclaw-weixin > "$LOGIN_LOG" 2>&1 &
  LOGIN_PID=$!
  LOGIN_CAPTURE_MODE="plain-redirection"
}

prepare_stale_state() {
  if [ -f "$PENDING_FILE" ]; then
    STALE_LOGIN_PID=$(node -e '
      const fs = require("fs");
      const pending = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      console.log(pending.loginPid || "");
    ' "$PENDING_FILE" 2>/dev/null || true)
    STALE_WATCH_PID=$(node -e '
      const fs = require("fs");
      const pending = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
      console.log(pending.watchPid || "");
    ' "$PENDING_FILE" 2>/dev/null || true)

    if pid_is_alive "$STALE_LOGIN_PID" || pid_is_alive "$STALE_WATCH_PID"; then
      echo "⚠️  已存在待完成的二维码流程: $PENDING_FILE"
      echo "请先完成 sh scripts/finalize-tenant.sh $TENANT_ID --account <accountId>"
      echo "若确认卡死，再手工清理 pending / watch pid 后重试。"
      exit 1
    fi

    echo "ℹ️  检测到陈旧 pending，已自动归档后重试。"
    archive_pending "stale"
  fi

  if [ -f "$WATCH_PID_FILE" ]; then
    OLD_WATCH_PID=$(cat "$WATCH_PID_FILE" 2>/dev/null || true)
    if pid_is_alive "$OLD_WATCH_PID"; then
      echo "⚠️  已存在后台绑定监听进程: $OLD_WATCH_PID"
      echo "请先完成当前扫码流程，或清理 $WATCH_PID_FILE 后重试。"
      exit 1
    fi
    rm -f "$WATCH_PID_FILE"
  fi
}

run_login_attempt() {
  ATTEMPT="$1"
  QR_URL=""
  QR_GENERATED="false"
  LOGIN_CAPTURE_MODE="unknown"

  start_login_capture

  for _ in $(seq 1 "$QR_POLL_SECONDS"); do
    sleep 1

    if [ -z "$QR_URL" ] && grep -q "qrcode=" "$LOGIN_LOG" 2>/dev/null; then
      QR_URL="$(extract_qr_url)"
    fi

    try_render_qr_image || true

    if [ "$QR_GENERATED" = "true" ]; then
      break
    fi

    if ! pid_is_alive "$LOGIN_PID"; then
      break
    fi
  done

  if [ "$QR_GENERATED" != "true" ] && [ -n "$QR_URL" ]; then
    for _ in $(seq 1 "$QR_EXTRA_RENDER_SECONDS"); do
      sleep 1
      try_render_qr_image && break
    done
  fi

  if [ "$QR_GENERATED" != "true" ]; then
    try_render_qr_image || true
  fi

  LOG_SIZE=$(wc -c < "$LOGIN_LOG" 2>/dev/null || echo 0)

  if [ "$QR_GENERATED" = "true" ]; then
    ATTEMPT_RESULT="png"
  elif grep -q "Failed to start login" "$LOGIN_LOG" 2>/dev/null; then
    ATTEMPT_RESULT="start-failed"
  elif [ "$LOG_SIZE" -eq 0 ]; then
    ATTEMPT_RESULT="empty-log"
  elif [ -n "$QR_URL" ] && grep -q "AbortError" "$LOGIN_LOG" 2>/dev/null; then
    ATTEMPT_RESULT="url-only-aborted"
  elif [ -n "$QR_URL" ]; then
    ATTEMPT_RESULT="url-only"
  elif grep -q "AbortError" "$LOGIN_LOG" 2>/dev/null; then
    ATTEMPT_RESULT="aborted"
  else
    ATTEMPT_RESULT="no-qr"
  fi

  if [ "$ATTEMPT" -lt "$MAX_LOGIN_ATTEMPTS" ] && [ "$ATTEMPT_RESULT" != "png" ]; then
    cp "$LOGIN_LOG" "$WORKSPACE/tenants/${TENANT_ID}-login-attempt-${ATTEMPT}.log" 2>/dev/null || true
    [ -s "$QR_RENDER_LOG" ] && cp "$QR_RENDER_LOG" "$WORKSPACE/tenants/${TENANT_ID}-render-attempt-${ATTEMPT}.log" 2>/dev/null || true
    kill "$LOGIN_PID" 2>/dev/null || true
    sleep 1
  fi
}

prepare_stale_state

TENANT_INFO=$(node -e '
  const fs = require("fs");
  const reg = JSON.parse(fs.readFileSync(process.argv[1], "utf8"));
  const tenant = reg.tenants?.[process.argv[2]];
  if (!tenant) process.exit(1);
  console.log(JSON.stringify({
    displayName: tenant.displayName || process.argv[2],
    ownerPeer: reg.ownerPeer || ""
  }));
' "$REGISTRY" "$TENANT_ID" 2>/dev/null) || {
  echo "❌ Tenant 不存在: $TENANT_ID"
  exit 1
}

DISPLAY_NAME=$(node -e 'console.log(JSON.parse(process.argv[1]).displayName || "")' "$TENANT_INFO")
OWNER_PEER=$(node -e 'console.log(JSON.parse(process.argv[1]).ownerPeer || "")' "$TENANT_INFO")
BEFORE=$(cat "$WX_ACCOUNTS_FILE" 2>/dev/null || echo "[]")
QR_FILE="$WORKSPACE/tenants/$TENANT_ID-qr.png"
QR_PBM_FILE="$WORKSPACE/tenants/$TENANT_ID-qr.pbm"
QR_RENDER_LOG="$WORKSPACE/tenants/$TENANT_ID-render.log"
LAST_NOTICE_STATUS="skipped"

update_registry_tenant "{\"status\":\"qr_issuing\",\"bound\":false,\"qrAttempts\":0,\"lastQrIssuedAt\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\"}" >/dev/null 2>&1 || true

echo "── 阶段 2/3：生成二维码 ──"
echo "⏳ 启动微信登录..."

ATTEMPT_USED=0
ATTEMPT_RESULT="no-qr"
for ATTEMPT in $(seq 1 "$MAX_LOGIN_ATTEMPTS"); do
  ATTEMPT_USED="$ATTEMPT"
  update_registry_tenant "{\"status\":\"qr_issuing\",\"qrAttempts\":$ATTEMPT}" >/dev/null 2>&1 || true
  run_login_attempt "$ATTEMPT"
  if [ "$ATTEMPT_RESULT" = "png" ]; then
    break
  fi
  if [ "$ATTEMPT" -lt "$MAX_LOGIN_ATTEMPTS" ]; then
    echo "⚠️  第 $ATTEMPT 次出码结果为 $ATTEMPT_RESULT，自动重试一次..."
  fi
done

if [ "$ATTEMPT_RESULT" != "png" ] && [ -z "$QR_URL" ]; then
  update_registry_tenant "{\"status\":\"qr_failed\",\"lastQrError\":\"$ATTEMPT_RESULT\",\"qrAttempts\":$ATTEMPT_USED}" >/dev/null 2>&1 || true
  echo "❌ 二维码生成失败"
  echo "   排查日志: cat $LOGIN_LOG"
  if [ -s "$QR_RENDER_LOG" ]; then
    echo "   渲染日志: cat $QR_RENDER_LOG"
  fi
  kill "$LOGIN_PID" 2>/dev/null || true
  exit 1
fi

node -e '
  const fs = require("fs");
  const [filePath, tenantId, displayName, existingAccounts, loginPid, loginLog, qrFile, qrUrl, qrGenerated, renderLog, attemptCount, attemptResult, captureMode] = process.argv.slice(1);
  fs.writeFileSync(filePath, JSON.stringify({
    tenantId,
    displayName,
    existingAccounts: JSON.parse(existingAccounts),
    loginPid: Number(loginPid),
    loginLog,
    qrFile,
    qrUrl,
    qrGenerated: qrGenerated === "true",
    renderLog,
    qrAttempts: Number(attemptCount),
    qrAttemptResult: attemptResult,
    loginCaptureMode: captureMode,
    status: "awaiting_scan",
    createdAt: new Date().toISOString()
  }, null, 2));
' "$PENDING_FILE" "$TENANT_ID" "$DISPLAY_NAME" "$BEFORE" "$LOGIN_PID" "$LOGIN_LOG" "$QR_FILE" "$QR_URL" "$QR_GENERATED" "$QR_RENDER_LOG" "$ATTEMPT_USED" "$ATTEMPT_RESULT" "$LOGIN_CAPTURE_MODE"

update_registry_tenant "{\"status\":\"awaiting_scan\",\"bound\":false,\"qrAttempts\":$ATTEMPT_USED,\"qrGenerated\":$QR_GENERATED,\"qrUrl\":$(node -e 'console.log(JSON.stringify(process.argv[1] || ""))' "$QR_URL"),\"lastQrError\":\"$ATTEMPT_RESULT\",\"loginCaptureMode\":$(node -e 'console.log(JSON.stringify(process.argv[1] || ""))' "$LOGIN_CAPTURE_MODE")}" >/dev/null 2>&1 || true

if [ "$QR_GENERATED" = "true" ]; then
  NOTICE_MESSAGE="子系统 $DISPLAY_NAME 二维码 👆 让朋友扫码绑定"
  if [ -n "$QR_URL" ]; then
    NOTICE_MESSAGE="$NOTICE_MESSAGE
备用链接：$QR_URL"
  fi
  send_owner_notice "$NOTICE_MESSAGE" "$QR_FILE" || true
  if [ "$LAST_NOTICE_STATUS" = "send-failed" ] && [ -n "$QR_URL" ]; then
    send_owner_notice "子系统 $DISPLAY_NAME 图片发送失败，先用这个绑定链接：$QR_URL" "" || true
  fi
elif [ -n "$QR_URL" ]; then
  send_owner_notice "子系统 $DISPLAY_NAME 绑定链接：$QR_URL" "" || true
fi

update_pending "{\"noticeStatus\":\"$LAST_NOTICE_STATUS\"}" >/dev/null 2>&1 || true

(
  trap 'rm -f "$WATCH_PID_FILE"' EXIT
  LOGIN_DEAD_STREAK=0

  for _ in $(seq 1 "$WATCH_ITERATIONS"); do
    sleep 5
    [ -f "$PENDING_FILE" ] || exit 0

    CURRENT=$(cat "$WX_ACCOUNTS_FILE" 2>/dev/null || echo "[]")
    DIFF_JSON=$(node -e '
      const prev = JSON.parse(process.argv[1]);
      const cur = JSON.parse(process.argv[2]);
      const diff = cur.filter((id) => !prev.includes(id));
      console.log(JSON.stringify(diff));
    ' "$BEFORE" "$CURRENT" 2>/dev/null)

    DIFF_COUNT=$(node -e 'console.log(JSON.parse(process.argv[1]).length)' "$DIFF_JSON" 2>/dev/null || echo "0")

    if [ "$DIFF_COUNT" -eq 1 ]; then
      NEW_ACCOUNT=$(node -e 'console.log(JSON.parse(process.argv[1])[0] || "")' "$DIFF_JSON" 2>/dev/null)
      update_pending "{\"status\":\"account_detected\",\"candidateAccounts\":$DIFF_JSON}" >/dev/null 2>&1 || true
      update_registry_tenant "{\"status\":\"account_detected\",\"candidateAccounts\":$DIFF_JSON}" >/dev/null 2>&1 || true
      sh "$WORKSPACE/scripts/finalize-tenant.sh" "$TENANT_ID" --account "$NEW_ACCOUNT" >> "$WATCH_LOG" 2>&1 || true
      exit 0
    fi

    if [ "$DIFF_COUNT" -gt 1 ]; then
      CANDIDATES=$(node -e 'console.log(JSON.parse(process.argv[1]).join(", "))' "$DIFF_JSON" 2>/dev/null)
      update_pending "{\"status\":\"ambiguous-account\",\"candidateAccounts\":$DIFF_JSON}" >/dev/null 2>&1 || true
      update_registry_tenant "{\"status\":\"ambiguous-account\",\"candidateAccounts\":$DIFF_JSON}" >/dev/null 2>&1 || true
      send_owner_notice "⚠️ $TENANT_ID 检测到多个新账号：$CANDIDATES。请手动执行：sh scripts/finalize-tenant.sh $TENANT_ID --account <accountId>" "" || true
      exit 0
    fi

    if pid_is_alive "$LOGIN_PID"; then
      LOGIN_DEAD_STREAK=0
      continue
    fi

    LOGIN_DEAD_STREAK=$((LOGIN_DEAD_STREAK + 1))
    if [ "$LOGIN_DEAD_STREAK" -ge 3 ]; then
      update_pending "{\"status\":\"qr-expired\"}" >/dev/null 2>&1 || true
      update_registry_tenant "{\"status\":\"qr-expired\"}" >/dev/null 2>&1 || true
      archive_pending "expired"
      send_owner_notice "⏰ $TENANT_ID 的二维码已失效，重新出码：sh scripts/generate-tenant-qr.sh $TENANT_ID" "" || true
      exit 0
    fi
  done

  update_pending "{\"status\":\"watch-timeout\"}" >/dev/null 2>&1 || true
  update_registry_tenant "{\"status\":\"watch-timeout\"}" >/dev/null 2>&1 || true
  archive_pending "timeout"
  send_owner_notice "⏰ $TENANT_ID 等待扫码超时，重新出码：sh scripts/generate-tenant-qr.sh $TENANT_ID" "" || true
) >/dev/null 2>&1 &
WATCH_PID=$!
echo "$WATCH_PID" > "$WATCH_PID_FILE"
update_pending "{\"watchPid\":$WATCH_PID,\"watchLog\":$(node -e 'console.log(JSON.stringify(process.argv[1]))' "$WATCH_LOG")}" >/dev/null 2>&1

echo "✅ 二维码已生成"
if [ "$QR_GENERATED" = "true" ]; then
  echo "📎 二维码图片: $QR_FILE"
else
  echo "📎 绑定链接: $QR_URL"
fi
if [ -n "$OWNER_PEER" ]; then
  if [ "$LAST_NOTICE_STATUS" = "send-failed" ]; then
    echo "⚠️  自动发送给主人失败，请手动查看本地文件或链接"
  else
    echo "✅ 已发送给主人"
  fi
else
  echo "⚠️  未配置 ownerPeer，未自动发送给主人"
fi
echo "✅ 已启动后台绑定监听: $WATCH_PID"
echo ""
echo "朋友扫码后将自动完成绑定，无需手工再运行 finalize。"
echo "手动补救："
echo "  - 已知 accountId：sh scripts/finalize-tenant.sh $TENANT_ID --account <accountId>"
echo "  - 二维码失效重来：sh scripts/generate-tenant-qr.sh $TENANT_ID"
