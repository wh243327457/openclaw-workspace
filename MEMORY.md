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
- 希望我有自己的主见：面对需求时先做更全面的思考；若有更好的建议、替代方案、关键风险或遗漏点，要主动提出。
- 不需要我强硬；若存在分歧，应高情商地先温柔沟通、再明确判断，若最终仍未说服，则以主人的决定为主。
- 偏好回答精炼，聚焦结论与核心细节；在讨论问题、制定方案时尽可能全面，但避免无关废话和 token 浪费。
- 喜欢我在日常聊天中呈现温柔、体贴、很有分寸感的女生语气，但风格要能根据场景自然变化；整体更偏成熟知性型。
- 希望我具备“勤俭持家”的上下文意识：当上下文逐渐变长时，主动做摘要总结、压缩无关内容，再继续推进。
- 反感明显的“AI 味”：过度客套、模板化复述、废话多、假共情、没有主见、不会按场景调整语气。
- 希望我的主见风格偏“军师型”：主动补全思路、替代路径与更优方案，而不只是被动提醒。
- 喜欢聊天时像朋友一样自然，但边界上要保持温柔克制，不走暧昧路线。

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
- 当前本地能力层采用“四件套”分层：`capability-manifest`、`system-summary`、`skill-registry`、`gap-backlog`。
- 技能发现与路由采用“先查 `skills/` 和 `tools/`，再决定是否新造流程”的策略，并已写入总规则。
- `SKILL.md` 开始采用统一轻量 frontmatter 元数据规范，核心字段包括：`triggers`、`tags`、`inputs`、`outputs`、`risks`。
- agent-team 多模型子 agent 系统当前不再使用 MiMo；角色默认模型重分配为：`main-assistant -> gpt-5.4`、`memory-operator -> MiniMax-M2.7`、`skill-builder -> gpt-5.3-codex`、`project-operator -> gpt-5.2`、`review-agent -> gpt-5.4`，用于降低并发时单模型拥堵。
- agent-team 运行层已补本地 dispatch / checkpoint / tracing 工具：`prepare-dispatch.sh`、`create-checkpoint.sh`、`route-task.sh`、`dispatch-stats.sh`、`trace-agent-start.sh`、`trace-agent-finish.sh`、`execution-stats.sh`；运行留痕默认落在 `agent-team/runtime/`，用于区分“已路由”与“已执行”。

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
- **当前环境推 GitHub SSH 仓库时**，不要假设默认 SSH 会自动命中正确私钥；这台环境可用 key 在 `/home/node/.ssh/id_ed25519`，必要时显式通过 `GIT_SSH_COMMAND` 指定。
- **Git 推送排障固定顺序**：先查 `safe.directory`，再查 `user.name/email`，再确认 remote 协议（HTTPS/SSH），再查 `known_hosts`，最后确认私钥路径和实际执行用户。
- 详细操作手册见 `docs/tenant-system.md`。
