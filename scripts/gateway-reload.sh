#!/bin/sh
# 触发 gateway 热重载
# 用法: sh scripts/gateway-reload.sh

set -e

OPENCLAW_BIN="${OPENCLAW_BIN:-openclaw}"
GATEWAY_SIGNAL_PID="${GATEWAY_SIGNAL_PID:-1}"
GATEWAY_RELOAD_MODE="${GATEWAY_RELOAD_MODE:-auto}"

if [ "$GATEWAY_RELOAD_MODE" = "skip" ]; then
  echo "⏭️  跳过 gateway 重载（GATEWAY_RELOAD_MODE=skip）"
  exit 0
fi

echo "🔄 触发 gateway 热重载..."
if node -e "process.kill(Number(process.argv[1]), 'SIGUSR1')" "$GATEWAY_SIGNAL_PID" 2>/dev/null; then
  sleep 3
  echo "✅ Gateway 重载完成"
  exit 0
fi

if $OPENCLAW_BIN gateway restart 2>&1 | grep -q "service disabled"; then
  echo "⚠️  gateway 是容器 PID 1，无法通过 CLI 重启。"
  echo "请手动重启容器，或者等待下次 gateway 启动时加载配置。"
  exit 1
fi

echo "✅ Gateway 已重启"
