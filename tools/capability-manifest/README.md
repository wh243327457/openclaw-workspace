# capability-manifest

只读能力清单工具。

用途：
- 盘点当前工作区里有哪些 agent、models、skills
- 生成结构化 JSON 清单
- 生成给人看的 Markdown 摘要

当前数据源：
- `agent-team/config.json`
- 工作区 `skills/*/SKILL.md`
- `exports/openclaw-skills/skills/*/SKILL.md`

运行方式：

```bash
python3 -m tools.capability_manifest.main json
python3 -m tools.capability_manifest.main markdown
```
