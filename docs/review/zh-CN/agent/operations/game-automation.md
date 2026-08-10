# 游戏自动化与崩溃处理

在启动、点击、悬浮、捕获、加载存档或检查游戏崩溃时阅读本文件。

## 进程与窗口

安装前关闭游戏。通过已解析的可执行文件启动，并把工作目录设为游戏目录：

```powershell
$game = Resolve-AtGGamePath $null
Start-Process -FilePath (Join-Path $game 'At The Gates.exe') -WorkingDirectory $game
```

仅看到窗口并不代表游戏已准备好。游戏内场景须等待选定状态标记或稳定目标界面。

### 烟测捕获限制

主菜单烟测的生命周期结论只对其拥有的 AtG 进程和窗口检查有效。当 Windows 拒绝
前台激活或其他全屏程序遮挡 AtG 时，`CopyFromScreen` 图像可能显示无关前台窗口。
这只是视觉捕获限制，不能作为 AtG 菜单或本地化结果证据；作出视觉 UI 声明前，应
以无遮挡的已拥有窗口捕获重跑。

可先尝试 computer-use。若 XNA 捕获失败，立即使用以下 Win32 脚本；其坐标相对
窗口：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Capture-AtGWindow.ps1 -OutputPath .\.tmp\run.png -MarkCursor
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Click-AtGWindow.ps1 -X 1280 -Y 714
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Move-AtGWindow.ps1 -X 1280 -Y 714
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Capture-Desktop.ps1 -OutputPath .\.tmp\desktop.png
```

可复现 UI 工作优先使用 `AtG.TestHarness` 与 JSON 场景库。每个相关测试会话使用一个
游戏进程和一次主菜单固定存档加载。不要从裁剪证据图推导悬浮坐标。

在当前 125% Windows 缩放下，harness 的 X/Y 是绝对客户端逻辑坐标，而保存的 PNG
使用缩放像素。只能从客户端坐标记录转换，绝不从截图抄坐标。地形与特质探索自动
覆盖已刻意禁用；用户明确批准后，Codex 可加载已归档场景中的固定存档并回放列出的
点位，但不得启动生成地块扫描或随机六点特质运行。任何反复创建随机世界的工作流
都需用户先确认，且流程在用户手动确认其行为正确前不得改变。

Win32 驱动会在每次绝对移动、点击、指纹和帧捕获前重新激活拥有的窗口，并用
`GetCursorPos` 验证光标；绝不回退到相对鼠标移动。

本工作区通过捆绑运行时启动测试 harness：
`& .\.tools\dotnet\dotnet.exe .\tools\AtG.TestHarness\bin\Release\net8.0-windows\AtG.TestHarness.dll ...`。
独立 `AtG.TestHarness.exe` 需要全局 .NET 8，无法在此处启动；捆绑运行时避免该环境
失败。其固定存档选择器会临时提升外部 Steam `Saved Games` 目录中的选定存档；在
沙箱中这需要范围受限的提升测试命令，访问被拒会在游戏启动前发生。`AtG.TestHarness`
先按 suite 过滤再应用 `--scenario`；手选场景的 suite 未勾选时，传入 `--suite All`
以避免表面成功但零点位的会话。

调用 harness 前，在已解析游戏的 `Saved Games` 目录中解析用户提供的世界关键词，
再通过 `--save-name`（或场景的 `SaveName`）传入精确文件名。`SaveSelectionLease`
只按时间戳提升该精确文件，不搜索用户配置文件、不推断世界 ID，也不隔离其他存档。
只有相对操作前时间戳/书签记录到新的操作后 `Crash.AtGLog` 事件（或匹配的进程
退出）时，加载列表失败才是当前证据；绝不从旧日志尾部推断。确认当前崩溃后，记录
并停止 UI 会话；不得创建新世界或悄悄扩大存档选择流程。

### 坐标校准门禁

场景 `X`/`Y` 值位于 harness 固定的 2560 x 1440 参考空间，运行时针对实际游戏客户
端转换。捕获是物理屏幕图像，其像素不会自动成为场景坐标。因此显示缩放、客户尺寸、
无边框/窗口状态和捕获原点都是运行时事实，不能视为记忆常量。

新定向点位在断言本地化文本前，必须在同一固定存档与界面完成校准：

1. 从用户图像记录意图的*控件身份*（如鱼群图标、家庭数量徽章、F3 外交按钮），
   而非附近面板或提示框。
2. 移至候选参考坐标，用 harness 光标标记捕获整个客户端。确认标记位于该控件且
   其预期稳定状态/提示可见；点击还要确认已到达命名目的界面，指纹变化并不足够。
3. 与候选一同记录参考尺寸、观察到的客户端/捕获尺寸、目标身份、存档名和标记
   结果。只有证明后，才可将点位提升到 `black-box-scenarios.json`。
4. 标记未命中、提示属于相邻控件或设置进入另一界面时，将点位以
   `UncalibratedCoordinate` 停止。不得运行 `ExpectedAll`/`ExpectedNo`、推断翻译
   回归，或仅依据截图反复调整坐标。

显示缩放、客户尺寸、窗口模式、捕获方法或设置路径改变时必须重新校准。原文所述
2026-07-30 ERJ-UUX 尝试是负面范例：六个输入坐标都绝对且稳定，但鱼点打开了
Shallow Water、氏族点未打开所需三条提示、所谓外交设置也未进入外交；这些是无效的
坐标证据，而非翻译结果。

## 悬浮与捕获规范

- 悬浮后等待 700–1500 ms；轮询最多到 3 秒。
- 仅在状态转换、失败或崩溃时保存全窗口图；通过点位保留裁剪图和结构化文本结果。
- 固定存档场景前从主菜单加载指定存档。除非被测行为本身是它，否则不得改用游戏内
  暂停菜单加载。
- 若随机地形、氏族、通知或命令暴露缺陷，保存状态，并在修复后重新加载同一存档。

## 崩溃流程

1. 捕获崩溃对话框，并记录点击前的 `Crash.AtGLog` 时间戳。
2. 点击确认按钮，让游戏刷新日志。
3. 等待退出或日志时间戳变化，然后读取最新日志块。
4. 记录触发动作、日志摘要、进程状态和截图摘要。日志是权威；图像只记录可见状态。
