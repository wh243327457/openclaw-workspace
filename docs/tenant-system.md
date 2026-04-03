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
   └── 写入 tenants/registry.json（此时还不碰绑定）

2. sh scripts/generate-tenant-qr.sh friend-001
   ├── 记录当前已有微信账号列表
   ├── 调用 openclaw channels login 生成二维码
   ├── 本地解析终端二维码字符画并渲染成 PNG
   ├── 若首轮只拿到链接/遇到 AbortError，会自动重试一次
   ├── 保存 pending 状态（含 qrAttempts / renderLog / noticeStatus）
   └── 输出/发送二维码图片 + URL

3. 把二维码发给朋友

4. 朋友用微信扫码
   ├── 微信绑定到机器人
   └── gateway 自动生成新 accountId（如 23a4b168c28e-im-bot）

5. sh scripts/finalize-tenant.sh friend-001
   ├── 对比前后账号列表，找出新增的 accountId
   ├── 使用 openclaw agents bind 写入 binding（accountId → agentId）
   ├── 更新注册表状态（binding / bound / active）
   └── 首条消息到达后自动写入 allowlist

   # 已知 accountId 时，也可以手动指定，避开多账号歧义：
   sh scripts/finalize-tenant.sh friend-001 --account 23a4b168c28e-im-bot

6. 触发 gateway 热重载
   └── 配置生效，朋友首条消息后自动加入白名单
```

> 默认推荐直接用：
>
> `sh scripts/create-tenant.sh "朋友名字"`

> 这会自动完成：创建 tenant → 生成二维码 → 发给主人 → 后台等待扫码并自动 finalize。
> 若二维码过期或后台监听超时，直接重跑：`sh scripts/generate-tenant-qr.sh <tenantId>`。

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

### registry 状态字段（新增约定）

每个 tenant 在 `tenants/registry.json` 中现在建议至少维护这些状态字段：

- `status`: `draft` / `qr_issuing` / `awaiting_scan` / `account_detected` / `binding` / `bound` / `active` / `ambiguous-account` / `qr-expired` / `watch-timeout` / `deleting`
- `bound`: 是否已完成 account 绑定
- `allowlisted`: 是否已进入 DM allowlist
- `accountId`: 已绑定微信账号（若已知）
- `peerId`: 首条消息识别到的对方 peerId（若已知）
- `qrAttempts`: 最近一次出码尝试次数

`registry.json` 应视作 tenant 控制面的主视图；`bindings`、`accounts.json`、`allowFrom.json` 为派生状态，需要定期巡检一致性。


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

### ❌ 坑 2：改配置后需要触发 gateway 重载

```bash
# gateway 是 PID 1，配置在内存中
# 不能直接改文件就生效，需要用 config.patch API 触发热重载：
sh scripts/gateway-reload.sh

# 原理：
# 1. config.get 获取当前配置 hash
# 2. config.patch 发送空补丁 + hash
# 3. gateway 发送 SIGUSR1 给自己，2秒后重启
# 不需要 docker restart！
```

### ❌ 坑 2.5：不要把二维码图片生成绑死在临时依赖上

旧方案依赖 `/tmp/node_modules/qrcode`，一旦临时依赖消失，就只能退回到链接。

现在的方案直接读取 `openclaw channels login` 打出来的终端二维码字符画，
本地转成 PBM/PNG，再发送给主人；这样即使没有额外 npm 包，也能稳定出图。

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
| `scripts/create-tenant.sh [name]` | 默认入口：创建 agent + 出二维码 + 自动等待绑定 | 新增子系统 |
| `scripts/generate-tenant-qr.sh <id>` | 生成二维码并保存 pending | 出码（阶段 2） |
| `scripts/finalize-tenant.sh <id>` | 手动完成绑定与白名单监听 | 手工补救（阶段 3） |
| `scripts/finalize-tenant.sh <id> --account <accountId>` | 已知账号时直接绑定，适合多账号歧义或自动流程失败 | 精确补救 |
| `scripts/delete-tenant.sh <id>` | 清理一切 | 删除子系统 |
| `scripts/healthcheck-tenant.sh [id]` | 巡检 tenant 的 registry / binding / accounts / allowlist 一致性 | 排查 / 验证 |
| `scripts/check-tenants.sh [id]` | `healthcheck-tenant.sh` 的简短入口 | 日常巡检 |
| `scripts/repair-tenant.sh <id> [--force]` | 清理陈旧 pending / watch pid，尝试恢复缺失的 binding 或 allowlist，并收敛 registry 状态 | 卡死补救 / 一致性修复 |

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

# 巡检某个 tenant 的状态一致性
sh scripts/check-tenants.sh friend-001

# 巡检所有 tenant
sh scripts/check-tenants.sh

# 修复某个 tenant 的陈旧 pending / 丢失 binding / allowlist 问题
sh scripts/repair-tenant.sh friend-001

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
>
> 当前二维码链路已增强为：
> - 优先发 PNG
> - 失败时降级到链接
> - 遇到 login AbortError / 只拿到链接时自动补一次重试
> - 优先用 TTY/`script` 方式捕获登录输出，降低空日志问题
> - 详细排障看 `tenants/*-login.log` 与 `tenants/*-render.log`
