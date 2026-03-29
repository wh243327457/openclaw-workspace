---
name: tenant-monitor
description: 管理和观测子系统。创建/绑定/删除朋友的独立 agent，查看子系统的规则、记忆、定时任务。当用户提到"子系统"、"朋友的系统"时使用。
---

# Tenant Monitor

## 管理命令

```bash
sh scripts/create-tenant.sh [名称]           # 创建子系统（自动编号）
sh scripts/bind-tenant.sh <id> <open_id>     # 绑定朋友
sh scripts/delete-tenant.sh <id>             # 删除子系统
sh scripts/list-tenants.sh                   # 查看状态
```

## 观测

通过读取 `~/.openclaw/workspace-<id>/` 目录：

- 规则：`SOUL.md`
- 记忆：`MEMORY.md` / `memory/YYYY-MM-DD.md`
- 定时任务：`cron.json`
- 用户信息：`USER.md`
- 身份：`IDENTITY.md`

所有观测为只读。
