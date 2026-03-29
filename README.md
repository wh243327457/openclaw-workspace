# OpenClaw Workspace Template

快速启动你的 OpenClaw AI 助手。

## 使用方法

```bash
# 克隆到 OpenClaw workspace 目录
git clone https://github.com/wh243327457/openclaw-workspace.git ~/.openclaw/workspace

# 运行初始化
sh ~/.openclaw/workspace/scripts/init-workspace.sh

# 启动 OpenClaw
openclaw gateway start
```

Agent 启动后会自动读取 `BOOTSTRAP.md`，引导完成初始化。

## 目录结构

```
~/.openclaw/workspace/
├── BOOTSTRAP.md          # 初始化指南（Agent 启动时自动读取）
├── SOUL.md               # Agent 性格模板
├── AGENTS.md             # 工作规范
├── MEMORY.md.template    # 长期记忆模板
├── USER.md.template      # 用户信息模板
├── agent-team/           # 模型配置管理系统
│   ├── config.json       # Agent 模型配置
│   ├── health-monitor.js # 模型健康监控
│   └── ui/               # Web 配置界面
├── docs/                 # 文档
└── scripts/              # 初始化脚本
```

## 私有依赖

此模板需要连接两个私有仓库：

```bash
# 技能仓库（skills、规则、工作流）
git clone https://github.com/wh243327457/openclaw-skills.git ~/.openclaw/workspace/exports/openclaw-skills

# 共享记忆仓库（多实例共享的长期记忆）
git clone https://github.com/wh243327457/openclaw-shared-memory.git ~/.openclaw/workspace/exports/openclaw-shared-memory
```

## 配置管理

启动后访问 `http://<宿主机IP>:8090` 管理模型配置。

## License

MIT
