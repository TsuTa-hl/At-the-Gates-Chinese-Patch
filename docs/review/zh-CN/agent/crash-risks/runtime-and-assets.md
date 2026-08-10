# 运行时、字体与重载风险（压缩审查译本）

> 原文包含近 1,900 行按会话累计的诊断历史。本审查副本仅翻译仍可复用的风险、
> 约束和验证结论；逐次时间线仍以原始
> `docs/agent/crash-risks/runtime-and-assets.md` 为准。

在修改 DynamicCjk、回退字体、文本校准、SpriteFont 引用、资产内存行为或从运行中
游戏加载存档时读取本文件。

## DynamicCjk

- `DynamicCjk` 保留原 SpriteFont 绘制拉丁文本、数字与私有区图标字形。CJK 通过
  `AtG.RuntimeText.dll` 和 `patch\Content\Fonts` 下捆绑的两份 OFL Noto Sans SC
  字体绘制。
- DynamicCjk 输出必须含 `patch\AtG.RuntimeText.dll`、两份字体文件，并且没有生成的
  合并字体 XNB。`.atg-merged-fonts` 仅属于回滚渲染器。
- 共享 CJK 图集最多 8 个 1024x1024 RGBA 页面（32 MiB）。缺失或无法分配的字形必须
  产生诊断和回退标记，绝不能进入 `SpriteFont.GetIndexForCharacter`。
- CJK 测量、行高、字形缓存键、基线和绘制路径必须使用同一校准描述符。当前校准为
  1.15 缩放加上随字号变化的小幅上移基线调整；绝不可施加到原始拉丁/图标路径。
- 渲染器、字体或翻译变更后，运行 `Test-FontPatchBudget.ps1`、
  `Test-RuntimeBuildReport.ps1` 和 `Test-FontReferences.ps1`。

## MergedFonts 回滚

- `MergedFonts` 仅在一个兼容周期内作为回滚路径。它只能安装标记的合并字体、保留
  原始图标字形，并使用 15 个 Segoe UI 子集构建。
- 绝不恢复废弃的 38 字体全语料构建：它会耗尽 32 位 XNA 内存。子集仍须覆盖全部 IL
  重写、`TEXT.Description.*` 与 config-node `Nodes.Value` 字形。

## 游戏内重载与内存生命周期

- 从运行中的主循环加载存档曾在地图对象、地形和精灵加载附近抛出
  `System.OutOfMemoryException`。将其视为内存压力症状，不能据此断言单一泄漏。
- `Build-GameLoadMemoryPatch.ps1` 必须保留 Large Address Aware EXE，并在已验证加载
  边界释放旧世界 SpriteBatch、清除已知静态世界根并强制回收。
- `ElfTools.Graphics.IdSpriteBatch.Dispose(bool)` 可释放自身索引缓冲，但不能释放共享
  `_defaultEffect`。
- 最终补丁输出使用 `tools\AtGFileOps.ps1` 的 `Copy-AtGFileIfChanged`，因为验证可能
  短暂使其处于内存映射状态。
- 固定回归存档应从主菜单加载，再经游戏内暂停菜单重载五次，且不更新 `Crash.AtGLog`
  或使私有字节单调增长。

## 性能与构建约束

- 使用仓库 SDK `.tools\dotnet\dotnet.exe` 构建和测试；环境 `PATH` 缺少 `dotnet`
  是执行环境故障，而非 runtime 或 harness 断言失败。
- 保持文本跟踪选择加入。性能摘要门禁检查活动帧 P95、上传峰值、回退/热活动、队列
  限额、图集页数、模式一致性及可选 LegacySync 比较。
- 字体预算、运行时构建报告、托管字体引用、warmset 架构和组合 catalog 都是静态门禁。
  全局 `git diff --check` 在脏工作区不应替代范围化实现文件检查。
- 输出 DLL/XML 的 Windows 映射锁是暂态或外部系统状态；确认没有中断子进程后重试
  正常暂存路径。不能把此类锁误归因于翻译或生成映射失败，更不能进行就地强写。

## 当前风险结论

- 主菜单烟测只证明生命周期、补丁加载和基础稳定性；未打开存档或目标提示时，不能
  当作目标界面的视觉验证。
- 固定存档/加载列表问题只有在触发操作后出现新的 `Crash.AtGLog` 事件或匹配进程退出
  时才是当前崩溃证据；旧日志尾部不是证据。
- 资源或测试依赖失败必须先在工具/夹具层修复；未进入游戏运行时的失败不能被报告为
  游戏崩溃。
