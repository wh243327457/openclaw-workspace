# 子任务使用指南

### 子任务系统的当前建议模型分工

- `main-assistant` -> `gpt-5.4`
- `memory-operator` -> `MiniMax-M2.7`
- `skill-builder` -> `gpt-5.3-codex`
- `project-operator` -> `gpt-5.2`
- `review-agent` -> `gpt-5.4`

### 已知问题
1. **大文件上下文导致 API 超时**：子任务读取大文件（>30KB）后，上下文膨胀，生成回复时网络超时断开
2. **MiMo 已不再续费，不再作为当前运行配置的一部分**：旧文档里提到的 MiMo 仅作为历史背景保留，不应继续作为默认执行模型

### 失败模式
```
子任务读取 3 个文件 → 上下文 ~18KB+ → 模型开始生成 → "Network connection lost"
```

## 最佳实践

### ✅ 推荐方式
1. **不读大文件，直接写**
   - 把文件内容的关键结构描述写在 task 里
   - 让子任务直接 write，不先 read

2. **拆分任务**
   - 不要一次写 40KB+ 的文件
   - 先写骨架，再逐步追加内容

3. **给足超时时间**
   - 复杂任务设置 `runTimeoutSeconds: 600`

4. **简单任务适合子任务**
   - 写小文件（<10KB）
   - 代码修改（edit 操作）
   - 数据处理
   - 搜索调研

### ❌ 避免
- 让子任务读取多个大文件再重写
- 一次性生成 30KB+ 的文件内容
- 给子任务太多步骤

## 标准错误恢复指令（粘贴到 task 末尾）

```
## ⚠️ 错误恢复（两层机制）

### 第一层：自行重试（最多 2 次）
遇到错误时：
1. 读取错误信息，判断原因
2. 调整策略重试：
   - 网络/API 超时 → 减少读取量，精简上下文
   - 文件过大 → 分块写入（先骨架后填充）
   - 工具调用失败 → 修正参数
3. 每次重试记录：做了什么 → 失败原因 → 改进方案

### 第二层：重试耗尽后上报主 Agent
最终回复必须包含 JSON 报告：
{"success":true/false, "completed_steps":[], "failed_at":"", "error":"", "retry_history":[], "suggestion":""}
```

### 第一层：子 Agent 自行处理（简单错误）
- 网络抖动 → 重试
- 语法错误 → 修正后重试
- 参数错误 → 检查后重试
- 最多重试 2 次

### 第二层：上报主 Agent（重试耗尽后）
子 Agent 在最终回复中必须包含：
```json
{
  "success": false,
  "completed_steps": ["已读取 config.json", "已规划新 UI 结构"],
  "failed_at": "write index.html",
  "error": "Network connection lost (OpenRouter timeout)",
  "retry_history": [
    {"attempt": 1, "action": "读取3个大文件后write", "reason": "上下文过大导致API超时"},
    {"attempt": 2, "action": "只读config.json后write", "reason": "仍然超时，文件内容33KB"}
  ],
  "suggestion": "建议主Agent直接写入，或分块写入"
}
```

主 Agent 收到后决策：
- 换更强的模型重新派子任务
- 自己直接做
- 拆分成更小的子任务
- 提示用户介入

### 好的子任务
```
写一个小脚本: 在 /tmp/test.js 中写一个 HTTP 服务器，监听 3000 端口
```

### 坏的子任务
```
读取 index.html (44KB)、config.json、server.js，然后重写 index.html
```
