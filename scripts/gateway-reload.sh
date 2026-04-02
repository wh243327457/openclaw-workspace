#!/bin/sh
# 触发 gateway 热重载
# 用法: sh scripts/gateway-reload.sh

set -e

echo "🔄 触发 gateway 热重载..."
if node -e "process.kill(1, 'SIGUSR1')" 2>/dev/null; then
  sleep 3
  echo "✅ Gateway 重载完成"
  exit 0
fi

if openclaw gateway restart 2>&1 | grep -q "service disabled"; then
  echo "⚠️  gateway 是容器 PID 1，无法通过 CLI 重启。"
  echo "请手动重启容器，或者等待下次 gateway 启动时加载配置。"
  exit 1
fi

echo "✅ Gateway 已重启"
