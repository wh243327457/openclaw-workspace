# 子系统（租户）架构

## 概述

支持多租户的子系统架构。每个朋友可以拥有独立的 agent 系统，与主系统完全隔离。

## 目录结构

```
~/.openclaw/workspace/
├── tenants/
│   ├── registry.json        ← 租户注册表
│   ├── routing.json         ← chatId → tenantId 路由
│   ├── friend-A/
│   │   ├── .tenant-meta.json ← 元数据（绑定码、绑定状态）
│   │   ├── SOUL.md
│   │   ├── USER.md
│   │   ├── MEMORY.md
│   │   ├── HEARTBEAT.md
│   │   ├── AGENTS.md
│   │   ├── IDENTITY.md
│   │   ├── TOOLS.md
│   │   ├── cron.json
│   │   ├── memory/
│   │   └── scripts/
│   └── friend-B/
│       └── ...
├── templates/
│   └── tenant-default/      ← 新租户初始化模板
└── scripts/
    ├── create-tenant.sh      ← 创建子系统
    ├── generate-bind-qr.sh   ← 生成绑定信息
    ├── bind-tenant.sh        ← 执行绑定
    ├── resolve-tenant.sh     ← 查询路由
    └── list-tenants.sh       ← 列出所有子系统
```

## 工作流程

### 1. 创建子系统

```bash
sh scripts/create-tenant.sh friend-alice "Alice"
```

- 复制模板到 `tenants/friend-alice/`
- 生成 6 位绑定码
- 写入注册表和元数据

### 2. 生成绑定信息

```bash
sh scripts/generate-bind-qr.sh friend-alice
```

- 输出绑定码和 QR JSON
- 发送给朋友

### 3. 朋友绑定

朋友发送 `bind:XXXXXX`（绑定码），或扫码触发绑定。

```bash
sh scripts/bind-tenant.sh ABC123 <朋友的chatId>
```

- 验证绑定码
- 更新元数据（.tenant-meta.json）
- 更新注册表（registry.json）
- 写入路由表（routing.json）

### 4. 消息路由

收到消息时，根据 chatId 查询路由：

```bash
sh scripts/resolve-tenant.sh <chatId>
```

- 返回 `tenants/friend-alice` → 使用该目录作为工作目录
- 返回 `main` → 使用主系统工作目录

### 5. 主系统观测

通过 `tenant-monitor` skill，主系统可以只读访问：
- 子系统的 SOUL.md（规则）
- 子系统的 MEMORY.md / memory/（记忆）
- 子系统的 cron.json（定时任务）
- 子系统的 scripts/（新增能力）

## 隔离规则

| 隔离维度 | 主系统 → 子系统 | 子系统 → 主系统 | 子系统 → 子系统 |
|---------|:---:|:---:|:---:|
| 记忆 | 👁 可观测 | ❌ 不可见 | ❌ 不可见 |
| 规则 | 👁 可观测 | ❌ 不可见 | ❌ 不可见 |
| 定时任务 | 👁 可观测 | ❌ 不可见 | ❌ 不可见 |
| 技能 | 👁 可观测 | ❌ 不可见 | ❌ 不可见 |
| 修改 | ❌ 不修改 | ❌ 不修改 | ❌ 不修改 |

## 扩展能力

后续可在子系统中添加：
- 独立的子 agent 角色（在 config.json 中按租户配置）
- 独立的 skills 目录
- 独立的模型配置
- 独立的健康监控
