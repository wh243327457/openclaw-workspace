#!/bin/sh
# 创建子系统工作目录
# 用法: sh scripts/create-tenant.sh <tenantId> [displayName]
#
# tenantId: 唯一标识（小写字母+数字+连字符，如 friend-alice）
# displayName: 显示名称（可选，默认等于 tenantId）

set -e

WORKSPACE="/home/node/.openclaw/workspace"
TENANTS_DIR="$WORKSPACE/tenants"
REGISTRY="$TENANTS_DIR/registry.json"
TEMPLATE="$WORKSPACE/templates/tenant-default"

TENANT_ID="${1:?用法: sh create-tenant.sh <tenantId> [displayName]}"
DISPLAY_NAME="${2:-$TENANT_ID}"

# 校验 tenantId 格式
echo "$TENANT_ID" | grep -qE '^[a-z0-9][a-z0-9-]*[a-z0-9]$' || {
  echo "ERROR: tenantId 只能包含小写字母、数字和连字符，且不能以连字符开头或结尾"
  exit 1
}

TENANT_DIR="$TENANTS_DIR/$TENANT_ID"

# 检查是否已存在
if [ -d "$TENANT_DIR" ]; then
  echo "ERROR: 子系统 '$TENANT_ID' 已存在于 $TENANT_DIR"
  exit 1
fi

# 复制模板
echo "创建子系统目录: $TENANT_DIR"
cp -r "$TEMPLATE" "$TENANT_DIR"

# 生成 bind code（6位随机码）
BIND_CODE=$(cat /dev/urandom | tr -dc 'A-Z0-9' | head -c 6)

# 写入租户元数据
cat > "$TENANT_DIR/.tenant-meta.json" << EOF
{
  "tenantId": "$TENANT_ID",
  "displayName": "$DISPLAY_NAME",
  "bindCode": "$BIND_CODE",
  "bound": false,
  "boundChatId": null,
  "boundAt": null,
  "createdAt": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "createdBy": "main-system"
}
EOF

# 更新注册表
TMP=$(mktemp)
node -e "
  const fs = require('fs');
  const reg = JSON.parse(fs.readFileSync('$REGISTRY', 'utf8'));
  reg.tenants['$TENANT_ID'] = {
    displayName: '$DISPLAY_NAME',
    dir: 'tenants/$TENANT_ID',
    bindCode: '$BIND_CODE',
    bound: false,
    boundChatId: null,
    createdAt: new Date().toISOString()
  };
  fs.writeFileSync('$TMP', JSON.stringify(reg, null, 2));
" && mv "$TMP" "$REGISTRY"

echo ""
echo "✅ 子系统创建成功"
echo "   ID:      $TENANT_ID"
echo "   名称:    $DISPLAY_NAME"
echo "   目录:    $TENANT_DIR"
echo "   绑定码:  $BIND_CODE"
echo ""
echo "下一步：运行 sh scripts/generate-bind-qr.sh $TENANT_ID 生成二维码"
