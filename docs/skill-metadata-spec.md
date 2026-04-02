# Skill Metadata Spec

这是一份给本地与共享技能使用的轻量元数据规范。

目标不是把 `SKILL.md` 搞复杂，而是补足最关键的机器可读信息，让模型和工具更稳定地发现、选择和复用技能。

## 设计目标

- 保持简单，不引入大而全 schema
- 优先服务技能发现、路由和注册表抽取
- 不破坏现有 `SKILL.md` 正文写法
- 允许旧技能渐进迁移

## 适用范围

适用于这些目录中的技能：

- `skills/*/SKILL.md`
- `exports/openclaw-skills/skills/*/SKILL.md`

## Frontmatter 字段

### 必填字段

```yaml
name: memory-keeper
description: Maintain local persistent memory for the assistant using daily logs, curated long-term memory, and topic files.
```

- `name`
  - 技能唯一名称
  - 使用小写字母、数字、连字符
- `description`
  - 一句话描述技能用途
  - 要写清“做什么”和“什么时候用”

### 推荐字段

```yaml
triggers:
  - remember this
  - prior context
  - persist memory

tags:
  - memory
  - persistence

inputs:
  - user preference
  - decision
  - conversation summary

outputs:
  - memory/YYYY-MM-DD.md
  - MEMORY.md
  - reviews/memory-promote-YYYYMMDD.md

risks:
  - privacy
  - over-retention
```

#### `triggers`

表示什么样的任务、说法、意图会触发该技能。

要求：
- 用短语，不写长句
- 优先写用户真实会说的话或高频意图
- 3 到 8 条足够

#### `tags`

表示技能所属主题，方便分类和检索。

建议标签：
- `memory`
- `skills`
- `review`
- `bootstrap`
- `sync`
- `tenant`
- `team`
- `ops`
- `content`
- `messaging`

#### `inputs`

表示技能通常接收什么输入。

例子：
- `user preference`
- `decision`
- `workspace status`
- `model config`
- `peer id`

#### `outputs`

表示技能典型会产出什么文件、结果或副作用目标。

例子：
- `memory/YYYY-MM-DD.md`
- `reviews/*.md`
- `agent-team/config.json`
- `tenant binding`

#### `risks`

表示这个技能最值得注意的风险点，不是越多越好。

例子：
- `privacy`
- `shared-memory leakage`
- `destructive change`
- `external side effect`
- `over-retention`

## 推荐模板

```md
---
name: memory-keeper
description: Maintain local persistent memory for the assistant using daily logs, curated long-term memory, and topic files. Use when the user asks to remember something, asks about prior context, or wants memory to persist across restarts.
triggers:
  - remember this
  - prior context
  - what do you remember
  - persist memory
tags:
  - memory
  - persistence
inputs:
  - user preference
  - decision
  - conversation summary
outputs:
  - memory/YYYY-MM-DD.md
  - MEMORY.md
  - reviews/memory-promote-YYYYMMDD.md
risks:
  - privacy
  - over-retention
---

# Memory Keeper

... 正文保持原有写法 ...
```

## 迁移策略

旧技能不要求一次性重写。

建议按这个顺序逐步迁移：

1. 先补 `triggers`
2. 再补 `tags`
3. 再补 `inputs` / `outputs`
4. 最后补 `risks`

这样成本最低，但对发现和路由的收益已经很大。

## 工具侧约定

`skill-registry` 应优先读取 frontmatter 字段。

规则：
- frontmatter 有值时，以 frontmatter 为准
- frontmatter 没值时，再从正文做轻量推断
- 不要为了补字段而在正文里过度猜测

## 不建议做的事

- 不要把长篇流程说明塞进 frontmatter
- 不要把正文内容机械重复到元数据里
- 不要给每个技能堆十几个字段
- 不要为了“看起来完整”而编造风险或输出

## 一句话原则

frontmatter 负责“机器怎么发现和路由”。

正文负责“技能具体怎么做”。
