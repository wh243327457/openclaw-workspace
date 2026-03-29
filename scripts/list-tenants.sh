#!/bin/sh
# 列出所有子系统
set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"

echo "🔧 OpenClaw Agents:"
openclaw agents list --bindings 2>&1 || echo "  (gateway 未连接)"

echo ""
echo "📋 子系统注册表:"

node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  const keys = Object.keys(reg.tenants);
  if (!keys.length) { console.log('  暂无'); process.exit(0); }
  keys.forEach(id => {
    const t = reg.tenants[id];
    console.log('  🟢 ' + t.displayName + ' (' + id + ')');
    console.log('     账号: ' + (t.accountId || '无'));
    console.log('     创建: ' + t.createdAt);
  });
  console.log('  共 ' + keys.length + ' 个');
"
