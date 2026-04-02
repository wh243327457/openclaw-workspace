---
name: tenant-monitor
description: 管理和观测子系统。创建/删除朋友的独立 agent，通过微信插件生成绑定二维码，查看子系统的规则、记忆、定时任务。
triggers:
  - 创建子系统
  - 删除子系统
  - 查看租户状态
  - 生成绑定二维码
  - tenant monitor
tags:
  - tenant
  - wechat
  - monitoring
  - ops
inputs:
  - tenant name
  - peer id
  - agent id
outputs:
  - tenant binding
  - 微信登录二维码
  - tenant status view
risks:
  - routing misconfiguration
  - wrong account binding
  - accidental tenant deletion
---

# Tenant Monitor

## 工作原理

每个子系统 = 一个独立的 OpenClaw agent + 一个独立的微信账号。

创建子系统建议走三段式：
- 阶段 1：创建 agent（独立工作目录）
- 阶段 2：单独生成微信登录二维码
- 阶段 3：朋友扫码后再绑定 `accountId → agent`

朋友扫码 → 微信绑定 → 消息自动路由到该 agent。

## 管理命令

```bash
sh scripts/create-tenant.sh [名称]             # 阶段 1：创建子系统
sh scripts/generate-tenant-qr.sh <id>          # 阶段 2：生成微信二维码
sh scripts/finalize-tenant.sh <id>             # 阶段 3：写路由 + 白名单监听
sh scripts/create-tenant.sh [名称] --with-qr   # 兼容一条龙：阶段 1 + 2
sh scripts/delete-tenant.sh <id>               # 删除子系统 + 清理微信账号
sh scripts/list-tenants.sh                     # 查看状态
sh scripts/bind-tenant.sh <id> <peer>          # 手动绑定（备用，仍直接改配置）
```

## 观测

通过读取 `~/.openclaw/workspace-<id>/` 目录：
- 规则：`SOUL.md`
- 记忆：`MEMORY.md` / `memory/YYYY-MM-DD.md`
- 定时任务：`cron.json`
- 用户信息：`USER.md`

所有观测为只读。
