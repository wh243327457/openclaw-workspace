---
name: tenant-monitor
description: 观测和管理子系统（租户）。用于查看朋友子系统的聊天记录、规则、定时任务、新增能力，以及创建/绑定/删除子系统。当用户提到"子系统"、"朋友的系统"、"租户"、"tenant"时使用。
---

# Tenant Monitor

管理和观测子系统的 skill。

## 子系统管理命令

### 创建子系统

```bash
sh /home/node/.openclaw/workspace/scripts/create-tenant.sh <tenantId> [displayName]
```

### 生成绑定信息

```bash
sh /home/node/.openclaw/workspace/scripts/generate-bind-qr.sh <tenantId>
```

### 绑定子系统

```bash
sh /home/node/.openclaw/workspace/scripts/bind-tenant.sh <bindCode> <chatId>
```

### 列出所有子系统

```bash
sh /home/node/.openclaw/workspace/scripts/list-tenants.sh
```

## 观测操作

所有观测操作通过直接读取 `tenants/<tenantId>/` 目录完成。

### 查看子系统规则

读 `tenants/<tenantId>/SOUL.md`

### 查看用户信息

读 `tenants/<tenantId>/USER.md`

### 查看记忆

- 长期记忆：读 `tenants/<tenantId>/MEMORY.md`
- 每日记忆：读 `tenants/<tenantId>/memory/YYYY-MM-DD.md`

### 查看定时任务

读 `tenants/<tenantId>/cron.json`

### 查看新增能力

对比 `tenants/<tenantId>/scripts/` 与模板 `templates/tenant-default/scripts/`

### 查看身份

读 `tenants/<tenantId>/IDENTITY.md`

### 查看心跳配置

读 `tenants/<tenantId>/HEARTBEAT.md`

## 汇总报告

可以对所有子系统批量读取，生成状态摘要。参考 `references/overview-report.md`。

## 注意事项

- 所有观测为只读，不要修改子系统的文件
- 子系统之间完全隔离，不互通
- 主系统的记忆和规则不暴露给子系统
