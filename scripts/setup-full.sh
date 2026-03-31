#!/bin/bash
# setup-full.sh - 一键初始化 OpenClaw workspace
#
# 用法: sh scripts/setup-full.sh [--proxy HOST:PORT] [--token TOKEN]
#
# 功能:
#   1. 自动探测或手动指定代理
#   2. 配置持久化代理环境变量和 git 代理
#   3. 克隆两个私有仓库（技能仓 + 共享记忆仓）
#   4. 清理 token 痕迹
#   5. 调用 init-workspace.sh 完成最终初始化

set -eu

# ─── 颜色 ───
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}✅ $1${NC}"; }
warn() { echo -e "  ${YELLOW}⚠️  $1${NC}"; }
fail() { echo -e "  ${RED}❌ $1${NC}"; }
info() { echo -e "  ${CYAN}ℹ️  $1${NC}"; }

# ─── 配置 ───
WS="${WORKSPACE:-/home/node/.openclaw/workspace}"
SKILLS_REPO="https://github.com/wh243327457/openclaw-skills.git"
MEMORY_REPO="https://github.com/wh243327457/openclaw-shared-memory.git"
PROXY_IPS=(172.18.0.1 172.17.0.1 172.26.192.1 192.168.4.177)
PROXY_PORTS=(7890 7891 7892 7893 1080 10808 10809)

# ─── Usage ───
usage() {
    cat << 'EOF'
用法: sh scripts/setup-full.sh [选项]

选项:
  --proxy HOST:PORT   指定代理地址（如 192.168.4.177:7893）
                      不指定则自动探测
  --token TOKEN       GitHub Personal Access Token
                      不指定则交互式提示输入
  -h, --help          显示帮助

示例:
  sh scripts/setup-full.sh --proxy 192.168.4.177:7893 --token ghp_xxx
  sh scripts/setup-full.sh  # 全自动探测 + 交互输入 token
EOF
    exit 0
}

# ─── 参数解析 ───
PROXY_ADDR=""
TOKEN=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --proxy)  PROXY_ADDR="$2"; shift 2 ;;
        --token)  TOKEN="$2"; shift 2 ;;
        -h|--help) usage ;;
        *) fail "未知参数: $1"; usage ;;
    esac
done

# ─── 第一步：代理配置 ───
echo ""
echo -e "${CYAN}=== 第一步：代理配置 ===${NC}"

proxy_found=""

if [ -n "$PROXY_ADDR" ]; then
    info "使用指定代理: $PROXY_ADDR"
    HOST="${PROXY_ADDR%%:*}"
    PORT="${PROXY_ADDR##*:}"
    if timeout 2 bash -c "echo > /dev/tcp/$HOST/$PORT" 2>/dev/null; then
        proxy_found="$PROXY_ADDR"
        ok "代理可达"
    else
        fail "指定代理 $PROXY_ADDR 不可达"
    fi
else
    info "自动探测代理..."
    for ip in "${PROXY_IPS[@]}"; do
        for port in "${PROXY_PORTS[@]}"; do
            if timeout 2 bash -c "echo > /dev/tcp/$ip/$port" 2>/dev/null; then
                proxy_found="$ip:$port"
                break 2
            fi
        done
    done
    if [ -n "$proxy_found" ]; then
        ok "探测到代理: $proxy_found"
    else
        warn "未探测到可用代理，将尝试直连"
    fi
fi

if [ -n "$proxy_found" ]; then
    # 写入 /etc/environment
    cat > /etc/environment << EOF
http_proxy=http://$proxy_found
https_proxy=http://$proxy_found
HTTP_PROXY=http://$proxy_found
HTTPS_PROXY=http://$proxy_found
EOF
    ok "环境变量已写入 /etc/environment"

    # 当前 shell 生效
    export http_proxy="http://$proxy_found"
    export https_proxy="http://$proxy_found"
    export HTTP_PROXY="http://$proxy_found"
    export HTTPS_PROXY="http://$proxy_found"

    # git 全局代理
    git config --global http.proxy "http://$proxy_found"
    git config --global https.proxy "http://$proxy_found"
    ok "Git 全局代理已配置"

    # 验证
    if curl -s --connect-timeout 10 -o /dev/null -w "" https://github.com 2>/dev/null; then
        ok "GitHub 连通性验证通过"
    else
        warn "GitHub 连通性验证失败，但代理端口可达，继续尝试"
    fi
else
    warn "跳过代理配置"
fi

# ─── 第二步：获取 Token ───
echo ""
echo -e "${CYAN}=== 第二步：GitHub 鉴权 ===${NC}"

if [ -z "$TOKEN" ]; then
    echo -n "请输入 GitHub Personal Access Token (ghp_开头): "
    read -r TOKEN
    if [ -z "$TOKEN" ]; then
        fail "Token 不能为空"
        exit 1
    fi
fi
ok "Token 已获取"

# ─── 第三步：克隆仓库 ───
echo ""
echo -e "${CYAN}=== 第三步：克隆仓库 ===${NC}"

mkdir -p "$WS/exports"

clone_repo() {
    local repo_url="$1"
    local target_dir="$2"
    local repo_name="$3"

    if [ -d "$target_dir/.git" ]; then
        warn "$repo_name 已存在，跳过克隆"
        return 0
    fi

    rm -rf "$target_dir"
    info "正在克隆 $repo_name..."

    # 构建带 token 的 URL
    local auth_url
    auth_url=$(echo "$repo_url" | sed "s|https://|https://$TOKEN@|")

    if git clone "$auth_url" "$target_dir" 2>&1; then
        ok "$repo_name 克隆成功"

        # 立即清理 token
        git -C "$target_dir" remote set-url origin "$repo_url" 2>/dev/null
        ok "Token 已从 $repo_name remote URL 中清除"

        # safe.directory
        git config --global --add safe.directory "$target_dir" 2>/dev/null
    else
        fail "$repo_name 克隆失败"
        return 1
    fi
}

clone_repo "$SKILLS_REPO" "$WS/exports/openclaw-skills" "技能仓库"
clone_repo "$MEMORY_REPO" "$WS/exports/openclaw-shared-memory" "共享记忆仓库"

# ─── 第四步：清理 Token 痕迹 ───
echo ""
echo -e "${CYAN}=== 第四步：安全清理 ===${NC}"

# 清理 shell 历史中的 token（尽力而为）
unset TOKEN 2>/dev/null
ok "Token 变量已清除"

# 提醒用户
warn "建议在 GitHub 撤销此 Token 并重新生成：https://github.com/settings/tokens"

# ─── 第五步：运行 init-workspace.sh ───
echo ""
echo -e "${CYAN}=== 第五步：初始化 Workspace ===${NC}"

INIT_SCRIPT="$WS/scripts/init-workspace.sh"
if [ -f "$INIT_SCRIPT" ]; then
    sh "$INIT_SCRIPT" "$WS"
else
    fail "init-workspace.sh 不存在: $INIT_SCRIPT"
fi

# ─── 汇总 ───
echo ""
echo -e "${CYAN}========================================${NC}"
echo -e "${CYAN}       setup-full.sh 执行完成           ${NC}"
echo -e "${CYAN}========================================${NC}"
echo ""

# 检查结果
[ -n "$proxy_found" ] && ok "代理: $proxy_found" || warn "代理: 未配置"
[ -d "$WS/exports/openclaw-skills/.git" ] && ok "技能仓库: 已连接" || fail "技能仓库: 未连接"
[ -d "$WS/exports/openclaw-shared-memory/.git" ] && ok "共享记忆仓库: 已连接" || fail "共享记忆仓库: 未连接"
[ -d "$WS/skills" ] && ok "Skills 软链接: 已创建" || warn "Skills 软链接: 未创建"

echo ""
echo -e "${GREEN}下一步：与 Agent 开始对话 🚀${NC}"
