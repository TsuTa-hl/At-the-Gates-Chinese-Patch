# 操作不变量

这些规则适用于每次构建、安装、烟测、验证和发布操作。

- 当工作跨越评估/修复、构建、安装、烟测、UI 测试或重试时，在工作流交接中携带同一条时间链。
- 统一验证会将所选检查、结果和阶段耗时存入任务本地 `.tmp` 证据；清理会保留文本交接。不要把常规测试结果变成知识文档。
- 文档专用任务使用无游戏的静态验证分支；它不会捕获源、安装补丁或启动烟测。
- Windows PowerShell 5.1 Desktop 是受支持的公共和开发 shell；仓库本地的 `.tools\dotnet\dotnet.exe` 是 .NET 工具链。对非 ASCII 文本显式使用 UTF-8。在单引号 PowerShell 字符串中，用两个单引号转义一个撇号。
- 按 `-GamePath`、`ATG_GAME_PATH` / `AT_THE_GATES_PATH`、Steam 发现的顺序解析游戏目录。绝不硬编码安装路径。
- 只要包含 `At The Gates.exe` 和 `Content\Text\English.xml`，玩家安装即为有效。不要向安装器添加版本、Steam 构建或文件哈希准入检查。
- 开发源捕获、构建、烟测和发布使用已恢复的当前 Steam 原版构建。`source/` 是可丢弃的本地输入，绝不是发布内容。
- 启动游戏时，将工作目录设置为已解析的游戏文件夹。所有坐标相对于游戏窗口，而不是虚拟桌面。
- 默认验证仅为主菜单烟测。黑盒场景和随机世界生成均需单独明确授权。
- 事务安装会备份实际安装前的文件。卸载必须逐字节恢复；只有补丁专有文件可以删除。
- 发布输出仅为玩家包：`README.md`、安装/卸载脚本和 `patch/`。开发材料不得进入该分支。

## 专题路由

- 构建、事务安装/卸载、统一验证：[build-and-install.md](operations/build-and-install.md)
- 游戏进程控制、截图和输入：[game-automation.md](operations/game-automation.md)
- 资源、网络和运行时诊断：[diagnostics.md](operations/diagnostics.md)
- 架构与数据流：[architecture.md](architecture.md)
- 当前验证状态：[current-status.md](current-status.md)
- 常见恢复路径：[troubleshooting.md](troubleshooting.md)
