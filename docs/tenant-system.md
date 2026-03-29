# 子系统（租户）运行手册

> 本文档描述 OpenClaw 微信子系统的完整架构、流程和操作指南。
> 避免重复踩坑，新人/未来的我能快速理解全貌。

## 一、架构概览

```
┌─────────────────────────────────────────────────┐
│                  Docker 容器                      │
│                                                   │
│  gateway (PID 1)                                  │
│    ├── 主 agent (main) ← 你的微信                  │
│    └── 子 agent (friend-001) ← 朋友的微信          │
│                                                   │
│  消息路由：                                        │
│    微信消息 → gateway → 查 binding → 路由到 agent   │
│    无 binding → fallback 到 main（或被拒绝）        │
└─────────────────────────────────────────────────┘
```

### 核心概念

| 概念 | 说明 |
|------|------|
| **agent** | 独立的 AI "大脑"，有自己的 workspace、记忆、会话 |
| **accountId** | 微信插件的登录实例 ID，由微信自动生成（如 `23a4b168c28e-im-bot`） |
| **binding** | 路由规则：`(channel, accountId) → agentId` |
| **DM Policy** | 谁能给机器人发消息：`pairing` / `allowlist` / `open` / `disabled` |
| **allowFrom** | 白名单文件，存储允许发消息的用户 peer ID |

## 二、完整流程

### 创建子系统

```
1. sh scripts/create-tenant.sh "朋友名字"
   ├── 创建 agent（openclaw agents add）
   ├── 初始化 workspace 模板
   ├── 记录当前已有微信账号列表
   ├── 调用 openclaw channels login 生成二维码
   └── 输出二维码图片 + URL

2. 把二维码发给朋友

3. 朋友用微信扫码
   ├── 微信绑定到机器人
   └── gateway 自动生成新 accountId（如 23a4b168c28e-im-bot）

4. sh scripts/finalize-tenant.sh friend-001
   ├── 对比前后账号列表，找出新增的 accountId
   ├── 写入 binding（accountId → agentId）
   ├── 将朋友的 peer ID 加入白名单
   └── 更新注册表

5. 重启容器（docker restart）
   └── gateway 重新读取配置，路由生效
```

### 删除子系统

```
sh scripts/delete-tenant.sh friend-001
├── 从白名单移除朋友的 peer ID
├── 移除 binding
├── 删除 agent（openclaw agents delete --force）
├── 清理注册表
├── 删除微信账号配置
└── 删除 workspace 和 agent 目录

重启容器后生效
```

## 三、关键配置文件

| 文件 | 作用 |
|------|------|
| `~/.openclaw/openclaw.json` | 主配置：agents、bindings、channels、dmPolicy |
| `~/.openclaw/openclaw-weixin/accounts.json` | 微信账号列表 |
| `~/.openclaw/credentials/openclaw-weixin-allowFrom.json` | DM 白名单 |
| `tenants/registry.json` | 子系统注册表 |
| `~/.openclaw/agents/<id>/sessions/` | agent 的会话记录 |
| `~/.openclaw/workspace-<id>/` | agent 的 workspace |

## 四、踩坑清单（血泪教训）

### ❌ 坑 1：不要用假的 accountId

```bash
# 错误：--account 参数不等于真实的 accountId
openclaw channels login --channel openclaw-weixin --account "friend-001"
# ↑ 这个 "friend-001" 只是标签，微信会生成自己的 ID

# 正确：登录后对比账号列表获取真实 ID
```

### ❌ 坑 2：改配置后必须重启容器

```bash
# 改了 openclaw.json 但不重启 → 不生效！
# gateway 是 PID 1，配置在内存中
# 必须从外部重启容器：
docker restart <容器名>
```

### ❌ 坑 3：删除 binding ≠ 拒绝对话

```bash
# 只删 binding → 朋友消息 fallback 到主系统
# 必须同时：
# 1. 设置 dmPolicy: "allowlist"
# 2. 维护白名单（finalize-tenant.sh 自动加，delete-tenant.sh 自动删）
```

### ❌ 坑 4：先想清楚再动手

完整的数据流：
```
用户扫码 → 微信生成 accountId → 写入 accounts.json
→ binding 匹配 accountId → 路由到 agent
→ DM policy 检查 peer ID → 白名单通过 → 处理消息
```

每一步的前置条件和副作用要想清楚再操作。

## 五、脚本清单

| 脚本 | 用途 | 时机 |
|------|------|------|
| `scripts/create-tenant.sh [name]` | 创建 agent + 生成二维码 | 新增子系统 |
| `scripts/finalize-tenant.sh <id>` | 绑定真实 accountId + 白名单 | 朋友扫码后 |
| `scripts/delete-tenant.sh <id>` | 清理一切 | 删除子系统 |

## 六、排查命令

```bash
# 查看当前绑定
openclaw agents bindings --json

# 查看微信账号
cat ~/.openclaw/openclaw-weixin/accounts.json

# 查看白名单
cat ~/.openclaw/credentials/openclaw-weixin-allowFrom.json

# 查看子系统注册表
cat tenants/registry.json

# 查看 agent 会话
ls ~/.openclaw/agents/<agentId>/sessions/

# 查看 agent 对话记录
node -e "
const fs = require('fs');
const lines = fs.readFileSync('会话文件.jsonl','utf8').trim().split('\n');
for (const line of lines) {
  const evt = JSON.parse(line);
  if (evt.type === 'message') {
    const msg = evt.message;
    let text = '';
    if (Array.isArray(msg.content)) {
      for (const c of msg.content) if (c.type==='text') text += c.text;
    }
    console.log(msg.role==='user'?'👤':'🤖', text.substring(0,200));
  }
}
"

# 查看渠道状态
openclaw channels status

# 查看渠道能力（是否支持媒体发送等）
openclaw channels capabilities --channel openclaw-weixin
```

## 七、发送图片给微信用户

```bash
openclaw message send \
  --channel openclaw-weixin \
  --account "1c4f88dcb914-im-bot" \
  --target "用户peerId@im.wechat" \
  --media "/path/to/image.png" \
  --message "说明文字"
```

> 注意：agent 本身没有发图片的工具，必须通过 `openclaw message send` CLI 命令。
> 账号用主账号（`1c4f88dcb914-im-bot`），target 用对方的 peer ID。
