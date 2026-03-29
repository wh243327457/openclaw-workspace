#!/bin/bash
# init-workspace.sh - 初始化 workspace 结构
#
# 用法: sh scripts/init-workspace.sh [workspace路径]
#
# 功能:
#   1. 创建必要的目录结构
#   2. 检查关键文件是否存在
#   3. 初始化 git（如果需要）
#   4. 输出状态报告

set -eu
WS="${1:-/home/node/.openclaw/workspace}"

echo "=== OpenClaw Workspace 初始化 ==="
echo "工作目录: $WS"
echo ""

# 创建必要目录
echo "📁 创建目录..."
for dir in memory memory/topics reviews skills scripts agent-team/ui exports; do
  mkdir -p "$WS/$dir"
done
echo "  ✅ 目录结构就绪"

# 从模板创建缺失的个人文件
echo ""
echo "📋 从模板创建个人文件..."
for f in USER.md MEMORY.md IDENTITY.md TOOLS.md; do
  if [ ! -f "$WS/$f" ] && [ -f "$WS/$f.template" ]; then
    cp "$WS/$f.template" "$WS/$f"
    echo "  ✅ $f (从模板创建)"
  fi
done

# 检查关键文件
echo ""
echo "📄 检查关键文件..."
ok=0; miss=0
for f in SOUL.md USER.md IDENTITY.md MEMORY.md TOOLS.md HEARTBEAT.md AGENTS.md; do
  if [ -f "$WS/$f" ]; then
    echo "  ✅ $f"
    ok=$((ok+1))
  else
    echo "  ⚠️  $f (不存在，将在首次对话时创建)"
    miss=$((miss+1))
  fi
done
echo "  存在: $ok, 缺失: $miss"

# 检查今日日记
TODAY=$(date +%Y-%m-%d)
if [ ! -f "$WS/memory/$TODAY.md" ]; then
  echo ""
  echo "📝 创建今日日记: memory/$TODAY.md"
  cat > "$WS/memory/$TODAY.md" << EOF
# $TODAY

## 日志
- $(date +%H:%M) Workspace 初始化完成
EOF
  echo "  ✅ 已创建"
fi

# 检查共享仓库
echo ""
echo "🔗 检查私有仓库..."
if [ -d "$WS/exports/openclaw-skills/.git" ]; then
  echo "  ✅ 技能仓库已连接"
  # 创建 skills 软链接
  if [ -d "$WS/exports/openclaw-skills/skills" ]; then
    ln -sfn "$WS/exports/openclaw-skills/skills" "$WS/skills"
    echo "  ✅ skills/ → exports/openclaw-skills/skills"
  fi
else
  echo "  ❌ 技能仓库未连接（必须）"
  echo "     运行: git clone <仓库URL> exports/openclaw-skills"
fi
if [ -d "$WS/exports/openclaw-shared-memory/.git" ]; then
  echo "  ✅ 共享记忆仓库已连接"
else
  echo "  ⚠️  共享记忆仓库未连接（可选）"
fi

# 检查 agent-team 配置
echo ""
echo "🤖 检查 Agent 团队配置..."
if [ -f "$WS/agent-team/config.json" ]; then
  echo "  ✅ config.json 存在"
else
  echo "  ⚠️  config.json 不存在"
fi
if [ -f "$WS/agent-team/ui/server.js" ]; then
  echo "  ✅ 配置管理 UI 存在"
else
  echo "  ⚠️  配置管理 UI 不存在"
fi

echo ""
echo "=== 初始化完成 ==="
echo ""
echo "下一步:"
echo "  1. 读取 BOOTSTRAP.md 了解完整流程"
echo "  2. 开始与主人对话"
echo "  3. 如需连接共享仓库，运行:"
echo "     git clone <仓库URL> exports/openclaw-skills"
echo "     git clone <仓库URL> exports/openclaw-shared-memory"
