# 工作流：清理工作区

## 目的

每项任务开始时执行一次。将可复用结论保留在精简文本交接中，然后只移除已知可再生
临时输出。

## 首先读取

- `docs/agent/knowledge-index.md`
- `docs/agent/operations.md`
- 仅在先前运行可能保护固定存档、活动场景或恢复记录时读取
  `docs/agent/black-box-tests.md`

## 步骤

1. 更改清理工具前先运行清理夹具：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Test-Clear-AtGWorkspace.ps1
   ```

2. 仅审计候选项，不改动文件：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Clear-AtGWorkspace.ps1 -TaskId <task-id> -WhatIf
   ```

3. 审阅建议的文本交接。移除可丢弃截图前，它必须保留场景/存档身份、坐标、失败文本、
   崩溃摘要、时间和结论。
4. 只有审计合理时才应用：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Clear-AtGWorkspace.ps1 -TaskId <task-id> -Apply
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Compact-AtGEvidenceReferences.ps1 -HandoffId <task-id>
   ```

## 边界

工具只能操作已批准的 `.tmp` 类别。不得删除 `source`、`patch`、`translations`、
`.cache`、`.tools`、游戏目录或存档。活动恢复数据与当前任务证据始终受保护。

`Clear-AtGEvidence.ps1` 是兼容入口；新工作使用 `Clear-AtGWorkspace.ps1`。
