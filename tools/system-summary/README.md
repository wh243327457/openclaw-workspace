# system-summary

系统状态摘要工具。

用途：
- 汇总当前工作区的关键运行状态
- 输出给人看的 Markdown 摘要
- 支持 JSON 结果，方便后续 UI 或其他工具复用

运行方式：

```bash
python3 -m tools.system_summary.main json
python3 -m tools.system_summary.main markdown
```
