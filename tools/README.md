# Tools Index

这个目录放本地小工具和系统辅助工具。

## 当前工具

### `capability-manifest`

用途：盘点当前工作区能力面。

- 读取 `agent-team/config.json`
- 扫描本地与导出技能目录
- 输出 agent / model / skill 清单

运行：

```bash
python3 -m tools.capability_manifest.main json
python3 -m tools.capability_manifest.main markdown
```

### `system-summary`

用途：汇总当前系统状态快照。

- 汇总 agent / model / skill / tenant / memory
- 检查 heartbeat 文件
- 检查 `8090` / `8091` 监听状态

运行：

```bash
python3 -m tools.system_summary.main json
python3 -m tools.system_summary.main markdown
```

### `skill-registry`

用途：生成技能注册表。

- 扫描 `SKILL.md`
- 提取 description、部分规则和组件信息
- 输出可读 Markdown 或结构化 JSON

运行：

```bash
python3 -m tools.skill_registry.main json
python3 -m tools.skill_registry.main markdown
```

### `gap-backlog`

用途：整理系统缺口与后续建设项。

- 记录能力缺口
- 给出优先级、状态和下一步建议
- 输出 Markdown 或 JSON

运行：

```bash
python3 -m tools.gap_backlog.main json
python3 -m tools.gap_backlog.main markdown
```

### `proxy-web-fetch`

用途：在当前代理环境下抓网页正文，绕开内建 `web_fetch` 对 `198.18.x.x` 的误判。

- 复用当前 `HTTP_PROXY` / `HTTPS_PROXY`
- 提取 text / markdown / json 三种输出
- 适合作为当前环境下的临时正文抓取替代工具

运行：

```bash
python3 -m tools.proxy_web_fetch_main https://docs.openclaw.ai --format markdown --max-chars 5000
python3 -m tools.proxy_web_fetch_main https://duckduckgo.com --format text --max-chars 2000
```

## 设计原则

- 先做只读工具
- 优先 JSON + Markdown 双输出
- 小而专，不做大而全
- 能复用就复用，不重复造轮子

## 下一步候选

- 更强的 `skill-registry` 字段提取
- `system-summary` 接入更多运行态信号
