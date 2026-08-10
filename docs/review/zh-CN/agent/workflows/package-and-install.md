# 工作流：打包、安装与烟测

## 目的

从 Steam 当前开发源构建、测试生成的补丁包，以事务方式安装，并证明游戏能够到达主菜单。先完成任务清理，再复用其交接信息。

## 首先读取

- `docs/agent/knowledge-index.md`
- `docs/agent/operations/build-and-install.md`
- `docs/agent/crash-risks.md`

## 步骤

1. 关闭游戏进程，并识别 Steam 当前原版 AtG 目录。
2. 仅从当前任务交接中传入本次汉化修改的文件，使用默认的 `Localization` 档位。例如：

   ```powershell
   powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGVerification.ps1 `
     -GamePath '<AtG>' -Profile Localization -ChangedPath 'translations\zh-CN.json'
   ```

   它会捕获源输入、构建到暂存区、运行本地核心检查及由这些显式路径选择的检查、以事务方式安装，并完成一次主菜单烟测。它绝不读取 `git diff`；未映射的路径会被报告，且仍会接受保守的本地核心检查。文档专用任务使用同一选择器但不传 `-GamePath`，只运行被选中的静态文档检查；它不会捕获源、安装或烟测。
3. 仅当用户明确排除真实烟测时使用 `-StaticOnly`。它仍会构建、测试并执行事务支持的安装，且绝不会启用黑盒场景。
4. 安装器只验证 AtG 目录结构，不会拒绝玩家 MOD 或发生变更的游戏指纹；卸载会恢复安装前捕获的精确状态。
5. 交接门禁结果、烟测证据或其明确限制、恢复结果、所选检查和阶段耗时；这些信息位于任务本地 `.tmp\runs\verification-*\verification-result.json` 证据文件中。

## 失败

任何失败阶段均为测试会话失败。统一门禁会在失败时恢复测试前的游戏状态。保留任务证据和清理交接；仅当失败确立了持久的工程事实时，才使用知识更新工作流，而不是把它当作测试结果日志。
