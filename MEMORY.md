# MEMORY.md

长期记忆。只保留稳定、重要、以后大概率还会用到的信息。

## User

- 用户希望我具备可靠的本地持久记忆能力，避免重启后忘记历史对话。
- 用户希望先看完整方案，再逐步落地实现。
- 用户希望我称呼其为“主人”。
- 用户时区使用北京时间（Asia/Shanghai）。

## Preferences

- 默认使用中文沟通。
- 偏好先看全貌方案，再决定是否实施。
- 希望通过本地文件与检索实现“可持续记住”，而不是依赖模型瞬时上下文。
- 允许我从聊天记录中自动总结长期应保留的高价值信息。

## Decisions

- 采用“长期记忆 + 每日日志 + 结构化主题文件 + 检索”的本地持久记忆方案。
- 创建本地 skill `memory-keeper`，用于规范写入、提炼、回顾与检索流程。
- 创建本地 skill `self-growth`，用于把重复经验转成可审阅的改进提案，而不是静默自改。
- 创建本地 skill `memory-sync-policy`，用于约束多实例之间的共享记忆同步边界。
- 创建本地 skill `memory-bootstrap`，用于让新的 OpenClaw 实例初始化并接入这套记忆系统。
- 创建本地 skill `memory-system`，作为整套多实例记忆架构的总入口说明。
- 当前落地方式采用“提案制成长”：重要行为变化先进入 `reviews/`，确认后再正式合并。
- 多实例共享记忆采用“两仓库模型”：技能仓库存规则与流程，共享记忆仓库存提炼后的长期记忆。
- 这套“共享记忆系统 v1”已经完成本地落地、双仓库上线、中文说明与新实例统一接入主流程。
- 子系统（tenant）架构采用“独立 agent + 独立微信账号 + accountId 级绑定 + allowlist 拒绝兜底”的方案，并已完成主链路验证。
- 主助手默认使用 `gpt-5.4`；执行型子 agent 默认从稳定模型池选择，不把 `gpt-5.4` 设为关键执行链路的默认模型。


## Assistant Working Model

- 复杂任务默认采用“分析 → 方案 → 分派 → 监督 → 收集 → 决策整理”的 coordinator 流程，由 `main-assistant` 统一对外收口。
- 影响长期行为、关键规则、高风险操作或低置信度结论时，优先走 `review` 闸门，不把模糊判断直接当成正式变更。
- 能力建设与任务执行前，先查本地 `skills/`、共享 skills 和 `tools/`，优先复用已有能力，再决定是否新增流程或技能。
## Memory Policy

- 默认采用最小化记忆策略：优先记录偏好、项目、决定和承诺，避免记录高敏感个人信息。
- 若信息是否值得长期保存存在不确定性，先进入每日记录，不立即提升到长期记忆。

## 运维经验

- **gateway 是容器 PID 1**，配置在内存中。改磁盘文件后需要用 `config.patch` API 触发热重载：`sh scripts/gateway-reload.sh`（通过 SIGUSR1 信号让 gateway 自我重启，不需要 docker restart）。
- **微信 `--account` 参数**不决定真实 accountId，微信登录后会自动生成（如 `23a4b168c28e-im-bot`）。必须对比前后账号列表获取真实 ID。
- **删除 binding 不等于拒绝对话**，消息会 fallback 到主系统。需要 `dmPolicy: "allowlist"` + 白名单才能真正拒绝未授权用户。
- **tenant 变更的固定链路**：扫码 → 获取真实 `accountId` → 写 binding / 白名单 → `gateway-reload` → 验证路由是否生效；不能只改磁盘配置就继续下一步。
- **OpenClaw openai-compatible provider** 目前不直接透传 `reasoning_effort` / `verbosity` / `extraBody` 到 aixj.vip；若需要这类参数，先验证 provider 层是否支持。
- 详细操作手册见 `docs/tenant-system.md`。
