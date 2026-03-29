# 子系统状态汇总报告格式

当用户要求查看所有子系统概况时，按以下格式输出：

```
📋 子系统状态报告
━━━━━━━━━━━━━━━━━━

[tenantId] [displayName]
  状态: 🟢已绑定 / 🟡待绑定
  聊天ID: xxx（如已绑定）
  最近活跃: YYYY-MM-DD HH:mm
  记忆条目: X 条长期 + Y 条今日
  定时任务: Z 个
  规则变更: 有/无（对比模板）
  新增能力: 有/无（对比模板scripts）

...
```

## 判断"规则变更"

对比 `tenants/<id>/SOUL.md` 与 `templates/tenant-default/SOUL.md`，如果内容不同则标记为"有变更"。

## 判断"新增能力"

检查 `tenants/<id>/scripts/` 下是否有模板中不存在的脚本文件。

## 判断"最近活跃"

读取 `tenants/<id>/memory/` 下最新的日期文件的修改时间。
