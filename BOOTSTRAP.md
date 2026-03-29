# BOOTSTRAP.md - 初始化指南

_你刚启动。先读这个文件，它告诉你一切。_

## 第一步：读取身份文件

按顺序读这些文件，了解你是谁、你服务谁：

1. `SOUL.md` — 你的性格和行为准则
2. `USER.md` — 你的主人是谁，怎么称呼
3. `IDENTITY.md` — 你的名字、风格、emoji

## 第二步：读取记忆系统

4. `MEMORY.md` — 长期记忆（如果存在）
5. `memory/` 目录下今天的日记（格式 `YYYY-MM-DD.md`）
6. `skills/memory-system/SKILL.md` — 记忆系统架构说明
7. `skills/memory-keeper/SKILL.md` — 日常记忆操作指南

## 第三步：检查工具

8. `TOOLS.md` — 本地工具配置（如果存在）
9. `HEARTBEAT.md` — 心跳任务配置

## 第四步：连接私有仓库（必须）

Skills 和共享记忆在私有仓库中，必须克隆才能完整运行：

```bash
# 1. 配置 git（替换为你的信息）
git config --global user.name "你的名字"
git config --global user.email "你的邮箱"

# 2. 克隆技能仓库（私有）
git clone https://github.com/wh243327457/openclaw-skills.git exports/openclaw-skills

# 3. 克隆共享记忆仓库（私有）
git clone https://github.com/wh243327457/openclaw-shared-memory.git exports/openclaw-shared-memory

# 4. 运行初始化脚本
sh scripts/init-workspace.sh
```

如果没有仓库访问权限，联系主人获取。

## 第五步：开始对话

不要机械地问"你好"。像这样开始：

> "我刚上线了。让我先看看我的记忆和配置。"

然后根据读到的内容自然地开始对话。如果 MEMORY.md 有内容，说明之前有对话历史，自然地接上。如果是全新，就从了解主人开始。

## 第六步：清理

全部完成后，你可以保留这个文件（它在心跳重启时有用），也可以选择删除。

---

## 文件目录速查

```
workspace/
├── BOOTSTRAP.md        ← 你现在读的文件
├── SOUL.md             ← 你的灵魂
├── USER.md             ← 主人信息
├── IDENTITY.md         ← 你的身份
├── MEMORY.md           ← 长期记忆
├── TOOLS.md            ← 工具配置
├── HEARTBEAT.md        ← 心跳任务
├── AGENTS.md           ← 工作规范
├── memory/             ← 每日日记
├── skills/             ← 本地技能
│   ├── memory-keeper/
│   ├── memory-system/
│   ├── self-growth/
│   └── ...
├── scripts/            ← 自动化脚本
├── agent-team/         ← Agent 团队配置
│   ├── config.json
│   ├── ui/             ← 配置管理界面
│   └── ...
├── exports/            ← 外部仓库挂载点
│   ├── openclaw-skills/
│   └── openclaw-shared-memory/
├── docs/               ← 文档
└── reviews/            ← 审核提案
```

_Good luck. Make it count._
