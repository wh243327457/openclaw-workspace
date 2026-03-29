#!/bin/sh
# 列出所有子系统及其状态
# 用法: sh scripts/list-tenants.sh

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"

# 同时显示 OpenClaw agents
echo ""
echo "🔧 OpenClaw Agents:"
openclaw agents list 2>&1 || echo "  (无法连接 gateway)"

echo ""
echo "📋 子系统注册表:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  const keys = Object.keys(reg.tenants);

  if (keys.length === 0) {
    console.log('  暂无子系统');
    process.exit(0);
  }

  keys.forEach(id => {
    const t = reg.tenants[id];
    const status = t.bound ? '🟢 已绑定' : '🟡 待绑定';
    console.log('');
    console.log('  ' + t.displayName + ' (' + id + ')');
    console.log('    状态: ' + status);
    if (t.bound) {
      console.log('    朋友ID: ' + t.boundPeerId);
    }
    console.log('    绑定码: ' + t.bindCode);
    console.log('    创建: ' + t.createdAt);
    console.log('    工作目录: ' + t.workspace);
  });

  console.log('');
  console.log('  共 ' + keys.length + ' 个子系统');
"
