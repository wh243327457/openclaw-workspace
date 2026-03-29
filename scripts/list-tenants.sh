#!/bin/sh
# 列出所有子系统及其状态
# 用法: sh scripts/list-tenants.sh

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"

node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  const tenants = reg.tenants;
  const keys = Object.keys(tenants);

  if (keys.length === 0) {
    console.log('暂无子系统');
    process.exit(0);
  }

  console.log('');
  console.log('📋 子系统列表');
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  keys.forEach(id => {
    const t = tenants[id];
    const status = t.bound ? '🟢 已绑定' : '🟡 待绑定';
    console.log('');
    console.log('  ' + t.displayName + ' (' + id + ')');
    console.log('    状态: ' + status);
    if (t.bound) {
      console.log('    聊天: ' + t.boundChatId);
    }
    console.log('    创建: ' + t.createdAt);
    console.log('    目录: ' + t.dir);
  });

  console.log('');
  console.log('共 ' + keys.length + ' 个子系统');
"
