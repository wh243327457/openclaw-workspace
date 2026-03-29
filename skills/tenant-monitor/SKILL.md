---
name: tenant-monitor
description: 观测和管理子系统（租户）。用于创建/绑定/删除朋友的独立 agent 系统，查看子系统的聊天记录、规则、定时任务、新增能力。当用户提到"子系统"、"朋友的系统"、"租户"、"tenant"时使用。
---

# Tenant Monitor

管理和观测子系统的 skill。

## 架构

- 每个子系统是一个 OpenClaw 原生 agent（独立工作目录、独立会话）
- 路由由 `openclaw.json` 中的 `bindings` 控制（基于 peer ID 匹配）
- 主系统通过 `tenants/registry.json` 追踪所有子系统

## 子系统管理

### 创建子系统

```bash
sh /home/node/.openclaw/workspace/scripts/create-tenant.sh <tenantId> [displayName]
```

自动完成：创建 agent + 初始化模板 + 生成绑定码

### 生成绑定信息

```bash
sh /home/node/.openclaw/workspace/scripts/generate-bind-qr.sh <tenantId>
```

### 绑定子系统

```bash
sh /home/node/.openclaw/workspace/scripts/bind-tenant.sh <bindCode> <peerId>
```

自动完成：添加 binding 到 openclaw.json + 更新注册表

### 删除子系统

```bash
sh /home/node/.openclaw/workspace/scripts/delete-tenant.sh <tenantId>
```

### 列出所有子系统

```bash
sh /home/node/.openclaw/workspace/scripts/list-tenants.sh
```

## 观测操作

通过 `openclaw agents list` 查看所有 agent 状态。
通过直接读取子系统工作目录进行观测：

- 规则：读 `~/.openclaw/workspace-<tenantId>/SOUL.md`
- 用户信息：读 `~/.openclaw/workspace-<tenantId>/USER.md`
- 长期记忆：读 `~/.openclaw/workspace-<tenantId>/MEMORY.md`
- 每日记忆：读 `~/.openclaw/workspace-<tenantId>/memory/YYYY-MM-DD.md`
- 定时任务：读 `~/.openclaw/workspace-<tenantId>/cron.json`
- 身份：读 `~/.openclaw/workspace-<tenantId>/IDENTITY.md`

## 注意事项

- 所有观测为只读，不要修改子系统的文件
- 子系统之间完全隔离
- 主系统的记忆和规则不暴露给子系统
- 绑定/删除后需要重启 gateway 生效
