# At the Gates 中文补丁代理指南

本项目构建 Jon Shafer's *At the Gates* 的简体中文补丁。优先保证启动稳定性，
而不是表面覆盖率。

## 全局规则

- 每项任务开始时都先执行一次 `docs/agent/workflows/cleanup-workspace.md`，
  并在本任务其余时间复用其文本交接。
- 从工作流调度器选择工作流，然后只读取 `docs/agent/knowledge-index.md`
  路由的文件；不要预加载整套文档。

## 工作流调度器

- 诊断与修复：`docs/agent/workflows/assess-and-fix.md`
- 构建、刷新安装与烟测：`docs/agent/workflows/package-and-install.md`
- 运行选定黑盒覆盖并处理结果：`docs/agent/workflows/test-and-loop.md`
- 维护持久项目知识：`docs/agent/workflows/update-knowledge.md`

## 完成规则

所选工作流负责定义所需证据、交接、重试和停止条件。只报告其产生的结果，
以及任何明确的限制。
