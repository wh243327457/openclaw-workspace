# 子代理系统方案 v2（稳健版）

> 在 v1 基础上，针对多实例常见故障做全面加固

---

## 已知风险与对策

### 风险 1：端口冲突
**问题**：多个实例争用同一端口，启动失败
**对策**：
- 主代理固定端口 18789
- 子代理从 18800 开始自动分配
- 端口分配记录在 registry.json
- 启动前检测端口占用

```
主代理:  18789
子代理A: 18800
子代理B: 18801
子代理C: 18802
```

### 风险 2：进程崩溃不恢复
**问题**：子代理进程挂掉后无人知晓，不会自动重启
**对策**：
- 每个子代理用 supervisor/s6 进程管理
- 主代理每 5 分钟检查子代理健康（调用 /api/config）
- 连续 3 次无响应 → 自动重启
- 重启失败 → 通知主人

```bash
# 子代理启动脚本（被 supervisor 管理）
#!/bin/bash
cd ~/.openclaw/workspace-$AGENT_NAME
exec openclaw gateway start --foreground
```

### 风险 3：API Key 并发限流
**问题**：多个实例共用同一个 API Key，触发速率限制
**对策**：
- 主代理和子代理使用不同的 API Key（如果可能）
- 或者在主代理中实现请求队列/代理层
- 子代理配置较低的请求频率
- 健康监控检测 429 错误并自动降速

### 风险 4：配置漂移
**问题**：子代理的配置被用户改乱，和主代理不一致
**对策**：
- 子代理的 config.json 从主代理模板生成
- 主代理定期检查子代理配置版本
- 不一致时可选择：同步/告警/强制覆盖
- 用户可改的部分（SOUL.md 等）和不可改的部分（模型池等）分开

### 风险 5：WeChat 会话断开
**问题**：子代理的微信绑定断开，用户发消息没人回
**对策**：
- 主代理监控子代理的 WeChat 连接状态
- 断开时自动尝试重连
- 重连失败通知主人重新扫码

### 风险 6：磁盘/内存耗尽
**问题**：多个实例同时运行，资源耗尽
**对策**：
- 资源限制：每个子代理最多 512MB 内存
- 日志轮转：子代理日志限制 10MB
- 定期清理：自动清理 30 天前的日记
- 主代理监控总体资源，超 80% 告警

### 风险 7：子代理无法找到依赖
**问题**：子代理启动时找不到 skills、脚本等
**对策**：
- 启动前运行 init-workspace.sh 检查所有依赖
- 缺失时自动从公开仓库拉取
- 关键依赖缺失 → 阻止启动并报告

### 风险 8：数据损坏
**问题**：主代理和子代理同时读写共享资源
**对策**：
- 主代理和子代理的工作空间完全隔离
- 主代理读子代理记忆时用只读方式（符号链接或定期复制）
- 不共享写入路径

---

## 架构设计

### 部署模式

**推荐：同机多进程**（不用 Docker 多实例，更简单）

```
~/.openclaw/
├── gateway/                    # 主代理
│   └── workspace/
│
├── sub-agents/                 # 子代理目录
│   ├── registry.json           # 子代理注册表
│   ├── alice/
│   │   ├── workspace/          # Alice 的工作空间
│   │   ├── gateway.toml        # Alice 的 OpenClaw 配置
│   │   └── supervisor.conf     # 进程管理配置
│   └── bob/
│       ├── workspace/
│       ├── gateway.toml
│       └── supervisor.conf
│
└── shared/                     # 共享资源（只读）
    ├── skills/                 # 从 openclaw-skills 同步
    └── templates/              # 工作空间模板
```

### 子代理注册表 (registry.json)

```json
{
  "agents": {
    "alice": {
      "name": "Alice 的助手",
      "owner": "alice-wechat-id",
      "port": 18800,
      "status": "running",
      "created": "2026-03-29T03:00:00Z",
      "wechat_bound": true,
      "inherited_skills": ["memory-keeper", "self-growth"],
      "last_health_check": "2026-03-29T03:30:00Z",
      "consecutive_failures": 0
    }
  }
}
```

### 子代理 gateway.toml（关键配置）

```toml
[gateway]
port = 18800
token = "alice-unique-token-xxx"

[agents.defaults]
defaultModel = "xiaomi/mimo-v2-pro"

[channels.weixin]
# Alice 的微信绑定配置
# 由主代理生成
```

### 进程管理（s6-supervisor）

每个子代理由 s6 或类似的 supervisor 管理：

```bash
# /etc/s6/alice/run
#!/bin/sh
exec chpst -u node openclaw gateway start \
  --config ~/.openclaw/sub-agents/alice/gateway.toml \
  --workspace ~/.openclaw/sub-agents/alice/workspace \
  2>&1 | logger -t alice
```

### 健康检查（主代理执行）

```bash
# 每 5 分钟检查一次
check_subagent() {
  local name=$1
  local port=$2
  local status=$(curl -s --max-time 5 "http://localhost:$port/api/config" -o /dev/null -w "%{http_code}")
  
  if [ "$status" = "200" ]; then
    echo "$name: healthy"
  else
    echo "$name: unhealthy ($status)"
    # 记录失败次数，达到阈值则重启
  fi
}
```

---

## 用户交互

### 子代理用户（通过微信）

```
# 基本对话
"你好" → 正常回复

# 配置指令（/ 开头）
/名字 小蓝           → 更新 IDENTITY.md
/性格 帮我改成温柔的    → 更新 SOUL.md  
/记忆 清理30天前的     → 清理旧日记
/状态                → 返回配置和状态
/帮助                → 列出所有指令
```

### 主代理管理者（你）

```
# 创建子代理
"创建一个子代理叫 alice，绑定微信 xxx"

# 查看状态
"所有子代理的状态"

# 查看聊天
"看看 alice 最近的聊天"

# 修改配置
"把 alice 的模型换成 gpt-5.4"

# 停止/启动
"停止 alice"
```

---

## 实现步骤

### Phase 1：基础框架
1. 创建子代理工作空间模板
2. 编写子代理启动/停止脚本
3. 实现 registry.json 管理
4. 端口自动分配

### Phase 2：进程管理
5. 集成进程 supervisor
6. 实现健康检查循环
7. 自动重启机制
8. 资源监控

### Phase 3：微信绑定
9. 子代理 WeChat channel 配置
10. 配置指令解析和处理
11. 用户权限控制

### Phase 4：主代理管理
12. 主代理的子代理管理命令
13. 记忆单向读取机制
14. 技能继承和过滤
15. 配置同步机制

### Phase 5：加固
16. 压力测试（多实例并发）
17. 故障注入测试
18. 日志聚合
19. 告警通知

---

## 关键配置清单

每个子代理启动前必须确认：

- [ ] 独立的 gateway token
- [ ] 独立的端口
- [ ] 独立的工作空间
- [ ] 独立的 API Key（或共享 Key 的限流配置）
- [ ] 独立的微信绑定
- [ ] 技能过滤已生效（无系统权限技能）
- [ ] 记忆目录已初始化
- [ ] 进程 supervisor 已配置
- [ ] 健康检查已注册

---

## 容易忽略的细节

### 1. Gateway Token 管理
每个子代理需要独立的 gateway token。生成方式：
```bash
# 自动生成
openssl rand -hex 32
```
token 存在子代理的 gateway.toml 中，主代理的 registry.json 记录引用（不存明文）。

### 2. 微信不能重复绑定
同一个微信只能绑定一个 OpenClaw 实例。所以：
- 子代理必须用**不同的微信号**
- 通常是创建新的 bot 微信号给子代理
- 主代理和子代理不能用同一个微信

### 3. 子代理不能访问宿主机
子代理应该有独立的 exec 安全策略：
```yaml
# 子代理的安全配置
agents.defaults.sandbox:
  exec:
    allowlist:
      - "git pull"
      - "git push"
    deny:
      - "rm -rf"
      - "docker"
      - "systemctl"
      - "openclaw gateway"
      - "curl"  # 防止子代理发起外部请求
```

### 4. 主代理崩溃时子代理怎么办
- 子代理继续运行（独立进程，不依赖主代理）
- 但子代理的健康检查会停止（因为是主代理在检查）
- 解决方案：子代理自身也有一层自检
- 主代理恢复后自动重新注册子代理

### 5. 子代理的 Cron 系统
- 子代理有独立的 cron 系统
- 但 cron 任务应该限制在子代理的工作空间内
- 禁止子代理创建修改系统级的 cron 任务

### 6. 版本同步
- 主代理更新 OpenClaw 版本后，子代理需要同步更新
- 方案：主代理执行 `openclaw update` 后，自动重启所有子代理
- 或者子代理自动检测更新（通过 healthcheck skill）

### 7. 日志隔离与聚合
```
~/.openclaw/logs/
├── main/               # 主代理日志
│   ├── gateway.log
│   └── agent.log
├── sub-agents/
│   ├── alice/
│   │   ├── gateway.log
│   │   └── agent.log
│   └── bob/
│       └── ...
```
主代理可以查看所有子代理日志，用于故障排查。

### 8. 子代理删除流程
```
1. 停止子代理进程
2. 断开微信绑定
3. 备份工作空间（可选）
4. 从 registry.json 移除
5. 清理 supervisor 配置
6. 删除工作空间目录（或保留备份）
```

### 9. 子代理记忆溢出防护
- 子代理的 memory/ 目录限制大小（如 100MB）
- 定期自动清理 30 天前的日记
- 长期记忆（MEMORY.md）不清理，但限制增长

### 10. 子代理通信隔离
- 子代理之间不能直接通信
- 如果需要通信，必须通过主代理中转
- 防止子代理 A 影响子代理 B 的行为

### 11. 子代理的网络访问限制
```yaml
# 子代理的网络安全策略
agents.defaults.sandbox:
  network:
    allow:
      - "api.openai.com"
      - "openrouter.ai"
    deny:
      - "*"  # 默认拒绝所有其他外部访问
```
防止子代理被用户引导访问恶意网站。

### 12. 子代理的通知机制
- 子代理的告警通知给主代理（不是直接给主人）
- 主代理汇总后统一通知主人
- 避免通知轰炸

### 13. 子代理的 AGENTS.md
每个子代理有独立的 AGENTS.md，但从主代理模板继承基本规则：
```markdown
# AGENTS.md（子代理版本）

## 基本规则（继承自主代理）
- 读取文件前先检查
- 不要发送半成品
- 默认使用中文

## 子代理特有规则
- 你是一个独立的助手，服务于你的主人
- 不要提及主代理或系统内部信息
- 你的记忆只属于你和你的主人
- 遇到无法处理的问题，告诉主人联系管理员
```

### 14. 子代理的 SOUL.md 限制
子代理的 SOUL.md 不能包含：
- 系统级指令
- 绕过安全限制的提示
- 访问主代理的指令

主代理创建子代理时会审核 SOUL.md 内容。

### 15. 并发创建保护
- 同时只能创建/启动一个子代理
- 防止端口分配冲突和资源竞争
- 创建过程加锁

### 16. 子代理的模型池
子代理有独立的模型配置（从主代理模板复制），但：
- 子代理只能用分配给它的模型
- 主代理可以在 registry 中限制子代理的可用模型
- 防止子代理消耗昂贵模型的配额

### 17. 微信封号风险
- 子代理用微信 bot 有封号风险
- 控制发送频率（每分钟不超过 10 条）
- 避免发送敏感内容
- 定期检测微信连接状态，异常时告警

### 18. 子代理的技能更新
- 主代理更新技能后，不会自动推送到子代理
- 子代理定期（每天）从公开仓库 pull 最新 skills
- 或主代理主动通知子代理更新
- 更新前子代理备份当前版本

### 19. 子代理备份与恢复
```bash
# 备份子代理
tar czf alice-backup-$(date +%Y%m%d).tar.gz ~/.openclaw/sub-agents/alice/

# 恢复子代理
tar xzf alice-backup-20260329.tar.gz -C ~/.openclaw/sub-agents/
sh scripts/start-subagent.sh alice
```

### 20. 子代理的安全审计
主代理定期审计子代理：
- 检查 SOUL.md 是否被篡改
- 检查 AGENTS.md 是否有绕过安全的内容
- 检查记忆中是否有敏感信息泄露
- 检查 skills 是否有未授权修改

---

## 完整检查清单（创建子代理时）

| # | 检查项 | 状态 |
|---|--------|------|
| 1 | 独立 gateway token 已生成 | ☐ |
| 2 | 端口已分配且未占用 | ☐ |
| 3 | 工作空间已初始化 | ☐ |
| 4 | SOUL.md 内容已审核（无越权指令） | ☐ |
| 5 | AGENTS.md 已使用子代理版本 | ☐ |
| 6 | 技能已过滤（无系统权限） | ☐ |
| 7 | 模型池已限制 | ☐ |
| 8 | API Key 已配置 | ☐ |
| 9 | 微信 channel 已配置 | ☐ |
| 10 | supervisor 已注册 | ☐ |
| 11 | 健康检查已加入主代理 | ☐ |
| 12 | 网络安全策略已设置 | ☐ |
| 13 | exec 安全策略已设置 | ☐ |
| 14 | 日志目录已创建 | ☐ |
| 15 | 备份目录已创建 | ☐ |
