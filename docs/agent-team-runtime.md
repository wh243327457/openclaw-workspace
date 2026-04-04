# Agent Team Runtime Notes

当前这套子 agent 系统的目标，不是只配置不同角色，而是让不同角色真的默认走不同模型，并形成稳定的调度闭环。

## 当前推荐角色模型

- `main-assistant` -> `gpt-5.4`
- `memory-operator` -> `MiniMax-M2.7`
- `skill-builder` -> `gpt-5.3-codex`
- `project-operator` -> `gpt-5.2`
- `review-agent` -> `gpt-5.4`

## 设计理由

- `main-assistant` / `review-agent` 负责对外、判断、收口，保留高质量模型
- `memory-operator` 偏记忆整理和归纳，使用更省成本、更稳的模型
- `skill-builder` 偏结构化规则与技能改造，使用强一点的 codex 线
- `project-operator` 偏执行与多步实施，和 `skill-builder` 分流，避免都堵在同一 codex 模型

## 快速路由

- 记忆/回忆/记住 -> `memory-operator`
- 技能/模板/工作流 -> `skill-builder`
- 多步执行/项目实施 -> `project-operator`
- 审查/风险/关键行为变更 -> `review-agent`
- 简单回答/短解释 -> `main-assistant`

## 本地脚本

- `sh scripts/route-task.sh <keyword>`
- `sh scripts/prepare-dispatch.sh <role> "<task-summary>" [output-file]`
- `sh scripts/create-checkpoint.sh`

## 当前注意点

- MiMo 已从运行配置移除，不再参与 fallback
- `kimi-k2.5` 在健康状态中长期处于 down，当前不应作为关键执行链路默认模型
- 这套系统之前的主要问题不是“没有 agent”，而是“缺本地 dispatch/checkpoint 脚本 + 角色默认模型过度集中”

## 运行判断

如果后面仍然感觉“系统没跑起来”，先检查：

1. 是否真的进行了子 agent 调度，而不是主助手自己全做
2. 是否使用了角色对应的默认模型
3. 是否触发了 fallback 并写回了 `agent-team/health-state.json`
4. 是否有 checkpoint / dispatch 留痕
