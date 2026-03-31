#!/bin/sh
# 子系统健康检查
# 用法: sh scripts/healthcheck-tenant.sh [tenantId]
# 如果不传 tenantId，检查所有 tenant

set -e

WORKSPACE="/home/node/.openclaw/workspace"
REGISTRY="$WORKSPACE/tenants/registry.json"
CONFIG="$HOME/.openclaw/openclaw.json"
ALLOW_FROM_FILE="$HOME/.openclaw/credentials/openclaw-weixin-allowFrom.json"
AGENTS_DIR="$HOME/.openclaw/agents"

# ANSI 颜色
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
fail() { echo -e "  ${RED}❌ $1${NC}"; }
info() { echo -e "  ${CYAN}ℹ️  $1${NC}"; }

check_tenant() {
    local TID="$1"
    local ISSUES=0
    local WARNINGS=0

    echo ""
    echo -e "${CYAN}━━━ $TID ━━━${NC}"

    # 读取注册表信息
    local DISPLAY_NAME ACCOUNT_ID
    DISPLAY_NAME=$(node -e "
        const fs = require('fs');
        const reg = JSON.parse(fs.readFileSync('$REGISTRY','utf8'));
        const t = reg.tenants['$TID'];
        console.log(t ? t.displayName : '(unknown)');
    " 2>/dev/null)
    ACCOUNT_ID=$(node -e "
        const fs = require('fs');
        const reg = JSON.parse(fs.readFileSync('$REGISTRY','utf8'));
        const t = reg.tenants['$TID'];
        console.log(t ? t.accountId : '');
    " 2>/dev/null)

    info "显示名: $DISPLAY_NAME"
    info "账号ID: ${ACCOUNT_ID:-未绑定}"

    # 检查 1: binding
    local HAS_BINDING
    HAS_BINDING=$(node -e "
        const fs = require('fs');
        const config = JSON.parse(fs.readFileSync('$CONFIG','utf8'));
        const b = (config.bindings||[]).find(b => b.agentId === '$TID');
        console.log(b ? b.match.accountId : '');
    " 2>/dev/null)
    if [ -n "$HAS_BINDING" ]; then
        ok "Binding: $HAS_BINDING → $TID"
    else
        fail "Binding 不存在"
        ISSUES=$((ISSUES+1))
    fi

    # 检查 2: agent workspace
    local WS_PATH
    WS_PATH=$(node -e "
        const fs = require('fs');
        const reg = JSON.parse(fs.readFileSync('$REGISTRY','utf8'));
        const t = reg.tenants['$TID'];
        console.log(t ? t.workspace : '');
    " 2>/dev/null)
    if [ -d "$WS_PATH" ]; then
        ok "Workspace: $WS_PATH"
    else
        fail "Workspace 不存在: $WS_PATH"
        ISSUES=$((ISSUES+1))
    fi

    # 检查 3: agent 目录
    if [ -d "$AGENTS_DIR/$TID" ]; then
        ok "Agent 目录: $AGENTS_DIR/$TID"
    else
        fail "Agent 目录不存在"
        ISSUES=$((ISSUES+1))
    fi

    # 检查 4: 白名单
    local FRIEND_PEER
    FRIEND_PEER=$(node -e "
        const fs = require('fs');
        const dir = '$AGENTS_DIR/$TID/sessions';
        try {
            if (!fs.existsSync(dir)) process.exit(0);
            const files = fs.readdirSync(dir).filter(f => f.endsWith('.json') && !f.startsWith('.'));
            for (const file of files) {
                try {
                    const s = JSON.parse(fs.readFileSync(dir+'/'+file,'utf8'));
                    if (s.origin && s.origin.from) {
                        console.log(s.origin.from);
                        process.exit(0);
                    }
                } catch(e) {}
            }
        } catch(e) {}
    " 2>/dev/null)

    if [ -n "$FRIEND_PEER" ]; then
        local IN_ALLOWLIST
        IN_ALLOWLIST=$(node -e "
            const fs = require('fs');
            try {
                const list = JSON.parse(fs.readFileSync('$ALLOW_FROM_FILE','utf8'));
                console.log(list.includes('$FRIEND_PEER') ? 'yes' : 'no');
            } catch(e) { console.log('no-file'); }
        " 2>/dev/null)

        if [ "$IN_ALLOWLIST" = "yes" ]; then
            ok "白名单: $FRIEND_PEER ✓"
        else
            fail "白名单缺失: $FRIEND_PEER 未加入"
            ISSUES=$((ISSUES+1))
            info "修复: node -e \"
                const fs=require('fs');
                const l=JSON.parse(fs.readFileSync('$ALLOW_FROM_FILE','utf8'));
                l.push('$FRIEND_PEER');
                fs.writeFileSync('$ALLOW_FROM_FILE',JSON.stringify(l,null,2));
            \""
        fi
    else
        warn "未检测到朋友的 peer ID（可能还未发消息）"
        WARNINGS=$((WARNINGS+1))
    fi

    # 检查 5: 最近会话时间
    local LAST_MODIFIED
    if [ -d "$AGENTS_DIR/$TID/sessions" ]; then
        LAST_MODIFIED=$(find "$AGENTS_DIR/$TID/sessions" -name "*.json" -o -name "*.jsonl" 2>/dev/null | xargs stat -c "%Y %n" 2>/dev/null | sort -rn | head -1 | cut -d' ' -f1)
        if [ -n "$LAST_MODIFIED" ]; then
            local NOW=$(date +%s)
            local DIFF=$((NOW - LAST_MODIFIED))
            local HOURS=$((DIFF / 3600))
            if [ "$HOURS" -lt 24 ]; then
                ok "最近活跃: ${HOURS}h 前"
            elif [ "$HOURS" -lt 168 ]; then
                warn "最近活跃: ${HOURS}h 前（>1天）"
                WARNINGS=$((WARNINGS+1))
            else
                warn "最近活跃: ${HOURS}h 前（>7天，可能不活跃）"
                WARNINGS=$((WARNINGS+1))
            fi
        else
            info "无会话记录"
        fi
    fi

    # 汇总
    echo ""
    if [ "$ISSUES" -eq 0 ] && [ "$WARNINGS" -eq 0 ]; then
        echo -e "  ${GREEN}状态: HEALTHY ✓${NC}"
    elif [ "$ISSUES" -eq 0 ]; then
        echo -e "  ${YELLOW}状态: WARN (${WARNINGS} warnings)${NC}"
    else
        echo -e "  ${RED}状态: FAIL (${ISSUES} issues, ${WARNINGS} warnings)${NC}"
    fi

    return "$ISSUES"
}

# ──── 主逻辑 ────
echo -e "${CYAN}=== 子系统健康检查 ===${NC}"

TENANT_ID="${1:-}"

if [ -n "$TENANT_ID" ]; then
    # 检查指定 tenant
    if ! node -e "
        const fs = require('fs');
        const reg = JSON.parse(fs.readFileSync('$REGISTRY','utf8'));
        if (!reg.tenants['$TENANT_ID']) { console.error('Tenant 不存在: $TENANT_ID'); process.exit(1); }
    " 2>/dev/null; then
        fail "Tenant 不存在: $TENANT_ID"
        echo "可用 tenant:"
        node -e "
            const fs = require('fs');
            const reg = JSON.parse(fs.readFileSync('$REGISTRY','utf8'));
            Object.keys(reg.tenants).forEach(k => console.log('  ' + k + ' (' + reg.tenants[k].displayName + ')'));
        " 2>/dev/null
        exit 1
    fi
    check_tenant "$TENANT_ID"
else
    # 检查所有 tenant
    TENANTS=$(node -e "
        const fs = require('fs');
        const reg = JSON.parse(fs.readFileSync('$REGISTRY','utf8'));
        Object.keys(reg.tenants).forEach(k => console.log(k));
    " 2>/dev/null)

    if [ -z "$TENANTS" ]; then
        info "没有配置任何 tenant"
        exit 0
    fi

    TOTAL=0
    HEALTHY=0
    WARN_COUNT=0
    FAIL_COUNT=0

    for tid in $TENANTS; do
        TOTAL=$((TOTAL+1))
        if check_tenant "$tid"; then
            HEALTHY=$((HEALTHY+1))
        else
            FAIL_COUNT=$((FAIL_COUNT+1))
        fi
    done

    echo ""
    echo -e "${CYAN}=== 总览 ===${NC}"
    echo -e "  总计: $TOTAL"
    echo -e "  ${GREEN}健康: $HEALTHY${NC}"
    [ "$FAIL_COUNT" -gt 0 ] && echo -e "  ${RED}异常: $FAIL_COUNT${NC}"
fi
