# 构建、事务与验证

对玩家可见的汉化改动使用统一门禁。只传入当前任务交接中明确列出的路径：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGVerification.ps1 `
  -GamePath 'D:\SteamLibrary\steamapps\common\Jon Shafer''s At the Gates' `
  -Profile Localization -ChangedPath 'translations\zh-CN.json'
```

`Localization` 是默认档位，依次执行以下操作：

1. 当 AtG 进程仍在运行时拒绝执行，避免修改可能尚未保存的游戏。
2. 在接触选定游戏目录前恢复锁定的测试依赖，因此包源失败不会要求恢复游戏。
3. 将已恢复的当前 Steam 输入捕获到 `source/`。
4. 构建到暂存区；仅在构建契约和报告验证后，才以原子方式替换 `patch/`。
5. 运行本地 C# 核心，以及由声明的路径类别选择的 PowerShell 检查。文本/XML、组合/运行时、托管重写、字体、自动化和文档修改各自选择专属检查。未分类路径会被报告且保留本地核心检查，绝不会被静默跳过。
6. 以事务方式安装到选定的 AtG 目录。
7. 运行由 xUnit 管理的主菜单烟测，并保留已验证补丁的安装状态。

当所有显式路径均为已分类的文档路径时，`Localization` 会改用仅文档的静态分支：不需要 `-GamePath`，只运行所选文档检查，不会捕获源、构建、安装或烟测。混合路径集或含未映射路径的路径集仍使用常规游戏门禁。

`Release` 不是常规开发的默认值。它只用于明确的 Codex 发布请求（以及 `Publish-AtGRelease.ps1`），并在同样的真实事务与烟测之前运行每个脚本和 .NET 组：完整目录/进度审计、发布包检查、模拟安装/卸载恢复矩阵及工具链回归。它的事务夹具会在 `tools/power-shell-test-suite.json` 中声明“游戏已停止”这一前置条件。

统一门禁会将源捕获、构建、每个选中测试组、安装和烟测的耗时，以及所选检查记录到 `.tmp\runs\verification-*\verification-result.json`。工作区清理会将该 JSON 保留为文本交接摘要。这是任务证据，而非知识文档。

`-StaticOnly` 是省略真实烟测的唯一显式方式。它仍会构建、运行静态套件并安装事务，但其结果必须报告为视觉验证限制。

## 直接调试命令

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Initialize-AtGSource.ps1 -GamePath '<AtG>' -Refresh
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Build-Patch.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ChinesePatch.ps1 -GamePath '<AtG>' -NoInstallNotice
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-ChinesePatch.ps1 -GamePath '<AtG>'
& .\.tools\dotnet\dotnet.exe test .\AtG.Patch.sln -c Release --no-restore -p:NuGetAudit=false
```

直接运行解决方案命令仅用于静态诊断。它不会选择 `ChangedPath`、安装补丁或运行真实游戏烟测；普通汉化任务或明确的发行门禁请使用统一门禁。

由于公共安装器默认会等待用户确认提示，非交互式代理刷新必须使用 `-NoInstallNotice`。它不会放松任何事务或游戏进程安全检查；面向玩家的手动安装仍会默认显示该提示。

直接安装器接受任何结构有效的 AtG 目录，绝不检查 Steam 构建指纹。它记录实际安装前的内容，包括与补丁路径重合的 MOD 文件。卸载会在删除事务数据前验证恢复后的字节；任何歧义均会保留恢复数据。

`Test-GameLaunch.ps1` 默认是主菜单烟测。不要在常规验证中加入 `-IncludeNewGame`；那属于黑盒覆盖。
