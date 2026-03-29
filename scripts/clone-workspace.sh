#!/bin/bash
# clone-workspace.sh - 克隆 workspace 模板到新实例
#
# 在新机器上运行:
#   sh clone-workspace.sh <workspace路径> <模板仓库URL>
#
# 或者直接从本地复制:
#   scp -r workspace/ new-machine:~/.openclaw/workspace/

set -eu
TARGET="${1:-$HOME/.openclaw/workspace}"
REPO="${2:-}"

echo "=== OpenClaw Workspace 克隆 ==="

if [ -n "$REPO" ]; then
  echo "从仓库克隆: $REPO → $TARGET"
  git clone "$REPO" "$TARGET"
else
  echo "请提供模板仓库 URL，或手动复制 workspace 目录"
  echo ""
  echo "方式 1 - 从仓库克隆:"
  echo "  sh clone-workspace.sh ~/.openclaw/workspace https://github.com/你的用户名/openclaw-workspace.git"
  echo ""
  echo "方式 2 - 从另一台机器复制:"
  echo "  scp -r ~/.openclaw/workspace/ new-machine:~/.openclaw/workspace/"
  echo ""
  echo "方式 3 - 直接下载 BOOTSTRAP.md (最小启动):"
  echo "  curl -o ~/.openclaw/workspace/BOOTSTRAP.md https://raw.githubusercontent.com/你的用户名/openclaw-workspace/main/BOOTSTRAP.md"
  exit 1
fi

# 运行初始化
if [ -f "$TARGET/scripts/init-workspace.sh" ]; then
  echo ""
  echo "运行初始化..."
  sh "$TARGET/scripts/init-workspace.sh" "$TARGET"
fi

echo ""
echo "✅ Workspace 就绪。启动 OpenClaw，Agent 会读取 BOOTSTRAP.md 自动初始化。"
