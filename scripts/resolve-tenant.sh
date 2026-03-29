#!/bin/sh
# 查询 chatId 对应的租户工作目录
# 用法: sh scripts/resolve-tenant.sh <chatId>
#
# 输出: 租户工作目录路径（绝对路径），或 "main" 表示主系统
#
# 用途: 消息路由时判断应该使用哪个工作目录

set -e

WORKSPACE="/home/node/.openclaw/workspace"
ROUTING="$WORKSPACE/tenants/routing.json"
TENANTS_DIR="$WORKSPACE/tenants"

CHAT_ID="${1:?用法: sh resolve-tenant.sh <chatId>}"

# 从 routing.json 查找
RESULT=$(node -e "
  const fs = require('fs');
  const routing = JSON.parse(fs.readFileSync('$ROUTING', 'utf8'));
  const tenantId = routing.routes['$CHAT_ID'];
  if (tenantId) {
    console.log('$TENANTS_DIR/' + tenantId);
  } else {
    console.log('main');
  }
")

echo "$RESULT"
