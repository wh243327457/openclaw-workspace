# Projects

## Local Persistent Memory System

- 状态：已完成第一阶段到共享模拟层的落地，双仓库已上线。
- 架构：采用"两仓库模型"，本地 daily memory 与共享长期记忆分层管理。
- 共享层约定：当前通过 `shared-memory/` 目录进行本地模拟，后续可替换为真实远程仓库检出。

## Agent Team System

- 状态：v1 基础规则层已完成并同步到远程 skills 仓库。
- 目标：建立多角色协作框架，支持可配置模型、备用模型池、自动路由与检查点机制。
- 接入方式：通过统一 bootstrap 脚本一条命令接入。

## Tenant System

- 状态：子系统（tenant）架构 v4 主链路已跑通。
- 当前方案：每个子系统 = 独立 agent + 独立微信账号；通过真实 `accountId` 做绑定，并配合 `allowlist` 避免解绑后消息 fallback 到主系统。
- 已完成：创建、绑定、删除、列出 tenant 的管理脚本；默认模板；注册表；只读观测能力。
- 下一步：补状态机化 registry、tenant 级自定义技能、以及创建→绑定→对话→删除→拒绝的固定回归测试。

## GPT-5.4 Provider Access

- 状态：已通过 `aixj.vip` 中转接入成功并完成基础验证。
- 关键约束：主助手可用 `gpt-5.4`，执行型子 agent 默认仍优先稳定模型池。
- 下一步：评估升级 OpenClaw 到 `2026.3.28` 后，复查 openai-compatible provider 的参数透传与配置行为。
