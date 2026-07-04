# 项目文件清单

本文按目录或文件类别记录仓库中各类文件的用途和清理规则。除非单个生成资源需要独立维护规则，否则不要逐个列出字体或游戏素材文件。

## 根目录

| 路径 | 用途 | 保留 / 清理规则 |
| --- | --- | --- |
| `AGENTS.md` | Agent 入口文档：全局规则、工作流调度、完成规则。 | 保持简短；细节放入 `docs/agent/`。 |
| `README.md` | 面向用户的补丁说明和常用命令。 | 保留。 |
| `Install-ChinesePatch.ps1` | 安装生成的补丁；安装前刷新由 manifest 管理的旧补丁。 | 保留。 |
| `Uninstall-ChinesePatch.ps1` | 按安装 manifest 恢复原文件。 | 保留。 |
| `.gitignore` | 排除生成证据、本地工具链和原始游戏资源。 | 保留。 |
| `.git/` | Git 元数据。 | 保留。 |
| `.agents/` | 本地 agent 元数据。 | 除非用户明确要求，否则不要编辑。 |
| `.git.invalid-*` | 旧的失败或重命名 Git 元数据目录。 | 若为空可删除。 |
| `Logs/` | 测试期间生成的本地游戏或运行日志。 | 不再需要时可删除；权威崩溃证据应记录在文档或 `.tmp/runs/`。 |

## 源文件、补丁产物和工具链

| 路径 | 用途 | 保留 / 清理规则 |
| --- | --- | --- |
| `source/` | 从游戏安装目录复制的原始 XML、DLL、字体和配置数据。 | 本地保留；不要上传；丢失后从游戏重新提取。 |
| `patch/` | 生成的安装载荷，包括汉化 XML、补丁 DLL/exe、字体和构建报告。 | 保留当前生成结果；可由 `tools/Build-Patch.ps1` 再生成。 |
| `.tools/` | 被忽略的仓库本地 .NET/NuGet 工具链，用于 IL rewrite。 | 本地保留；可由 `tools/Install-DotNetToolchain.ps1` 再生成。 |
| `.tmp/` | 被忽略的截图、contact sheet、试探性汉化证据和临时输出。 | 保留文档引用到的证据；清理前先运行 `tools/Clear-AtGEvidence.ps1 -WhatIf`。 |

## 翻译输入

| 路径 | 用途 | 保留 / 清理规则 |
| --- | --- | --- |
| `translations/zh-CN.json` | 主 `English.xml` 翻译表。 | 保留。 |
| `translations/config-node-strings.json` | 安全配置节点翻译。 | 保留。 |
| `translations/config-node-extra-strings.json` | 后续发现的额外安全配置节点翻译。 | 保留。 |
| `translations/hardcoded-ui-il-rewrite.json` | UI DLL 主要 IL rewrite 映射；避免 padding 并降低排版问题。 | 保留。 |
| `translations/hardcoded-common-il-rewrite.json` | Common DLL 中已接受的显示安全字符串映射。 | 保留。 |
| `translations/hardcoded-game-il-rewrite.json` | Game DLL 中已接受的显示安全字符串映射。 | 保留。 |
| `translations/hardcoded-ui-il-strings.json` | 旧 UI IL 字符串补丁输入。 | 在完全迁移并验证未使用前保留。 |
| `translations/hardcoded-strings.json` | UI 硬编码字符串 byte patch fallback。 | 在被已验证 IL rewrite 替代前保留。 |
| `translations/hardcoded-common-strings.json` | Common DLL 字符串 byte patch fallback。 | 保留；Common 仍属高风险来源。 |
| `translations/hardcoded-ui-offsets.json` | 已验证的 UI offset fallback 补丁。 | 只要仍有 fallback 被引用就保留。 |
| `translations/hardcoded-common-offsets.json` | 已禁用或实验性的 Common offset 记录。 | 作为风险文档保留；默认不得启用。 |
| `translations/tag-glossary.json` | 翻译与标签辅助术语表。 | 保留。 |
| `translations/common-chars.txt` | 字体 glyph 覆盖用字符集输入。 | 保留。 |
| `translations/entries.csv` | 表格友好的翻译 / 参考导出。 | 若仍用于审查则保留。 |
| `translations/trial-*.json` | 试探性快速失败批次输入，以及已接受 / 已拒绝字符串的证据。 | 保留到其尝试状态被稳定写入 `docs/agent/trial-localization-state.json` 和 `docs/review/known-texts.csv`。 |

## 工具

| 文件 | 用途 | 保留 / 清理规则 |
| --- | --- | --- |
| `tools/AtGManagedMetadata.ps1` | 托管程序集元数据共享 helper。 | 保留。 |
| `tools/AtGPaths.ps1` | 按参数、环境变量和 Steam 自动定位游戏路径。 | 保留。 |
| `tools/AtGTiming.ps1` | 阶段耗时摘要 helper。 | 保留。 |
| `tools/Build-*.ps1` | 构建汉化 XML、配置补丁、硬编码补丁、IL rewrite、offset patch、字体和最终补丁载荷。 | 保留。 |
| `tools/Capture-*.ps1`、`Click-AtGWindow.ps1`、`Move-AtGWindow.ps1` | XNA 窗口的 Win32 截图、点击和悬停 fallback。 | 保留。 |
| `tools/Crop-AtGImage.ps1`、`New-AtGContactSheet.ps1` | 裁剪和视觉测试证据拼图工具。 | 保留。 |
| `tools/Export-*.ps1` | 导出文本条目、静态候选、DLL `ldstr` 目录和审查表。 | 保留。 |
| `tools/Find-Utf16String.ps1` | 查找 UTF-16 字符串，用于旧 byte / offset patch。 | fallback patch 仍存在时保留。 |
| `tools/Get-AtGWindow.ps1` | 为自动化脚本定位游戏窗口。 | 保留。 |
| `tools/Install-DotNetToolchain.ps1` | 安装仓库本地 .NET 工具链供 IL rewrite 使用。 | 保留。 |
| `tools/Invoke-AtGBlackBoxScenario.ps1` | 在已打开的游戏状态中执行记录的黑盒场景点。 | 保留。 |
| `tools/Invoke-AtGTrialLocalizationBatch.ps1` | 执行试探性快速失败批次，并在失败时二分定位问题文本。 | 保留。 |
| `tools/New-Xna*.ps1` | 构建 / 合并 XNA SpriteFont 资源并保留原图标 glyph。 | 保留。 |
| `tools/Test-*.ps1` | 静态、构建、安装、烟测、schema、审查和回归测试。 | 保留。 |
| `tools/Test-GameLaunchMainLoopGate.ps1` | 回归测试：确保烟测等待主循环标记，而非地图生成早期阶段。 | 保留。 |
| `tools/Test-GameLaunchSingleInstanceGuard.ps1` | 回归测试：确保烟测脚本持有单实例锁时，重复调用会在启动游戏前失败。 | 保留。 |
| `tools/Test-TrialLocalizationRecoveryGuard.ps1` | 回归测试：确保中断的试探性汉化批处理会在下一次运行前恢复 baseline map。 | 保留。 |
| `tools/Test-TrialLocalizationBatchSafety.ps1` | 回归测试：确保试探性批次在 PlanOnly 阶段拒绝 `ConvertTags`、方括号解析 token 和 U+FFFD 乱码。 | 保留。 |
| `tools/Test-IlRewriteMappedFileRetry.ps1` | 回归测试：确保 IL rewrite 构建脚本会重试 Windows mapped-file 瞬时写入失败。 | 保留。 |
| `tools/Test-FontPatchRemovalRetry.ps1` | 回归测试：确保重新生成字体前删除旧字体目录时会重试 Windows 瞬时访问拒绝。 | 保留。 |
| `tools/Test-AtGWindowFinderFallback.ps1` | 回归测试：确保 Win32 自动化可从 `EnumWindows` fallback 到游戏进程 `MainWindowHandle`。 | 保留。 |
| `tools/AtG.IlRewrite/` | C# dnlib IL rewrite 工具项目。 | 保留；`bin/obj` 继续忽略。 |

## 文档

| 路径 | 用途 | 保留 / 清理规则 |
| --- | --- | --- |
| `docs/agent/workflows/*.md` | 评估修复、打包安装烟测、测试循环、知识更新等工作流模块。 | 保持流程聚焦。 |
| `docs/agent/operations.md` | 命令和自动化操作细节。 | 保留；不要复制到 `AGENTS.md`。 |
| `docs/agent/text-sources.md` | 文本来源安全性、提取规则和补丁优先级。 | 保留。 |
| `docs/agent/crash-risks.md` | 已知崩溃类型和必要绕开规则。 | 保留。 |
| `docs/agent/translation-style.md` | 语气、术语、UI 文案和可接受显示例外。 | 保留。 |
| `docs/agent/black-box-tests.md` | 人类可读的黑盒测试策略和场景状态。 | 保持精简；详细点位放入 JSON。 |
| `docs/agent/black-box-scenarios.json` | 机器可读的全量 / 增量场景库。 | 保留。 |
| `docs/agent/trial-localization-state.json` | 机器可读的试探性汉化状态：批量策略、已尝试批次、已拒绝单条、catalog 精度问题和下一步优先级。 | 给 agent / 脚本恢复任务使用；不要作为人工译文审查表。 |
| `docs/agent/spark-delegation.md` | `GPT-5.3-codex-spark` 直接访问工程时的必读指南：可执行任务、停止条件、提示模板和结果格式。 | 保留；只记录低等级模型执行规则，不承载具体批次证据。 |
| `docs/review/known-texts.csv` | 供人工审查的表格：来源、类型、原文、译文、状态、`ReviewState`、`ReasonCode`、安全性、备注和定位信息。 | 文本来源或翻译映射变化后重新生成；不再保留 Markdown 副本。 |
| `docs/review/project-inventory.md` | 本文件：项目清单和清理记录。 | 文件或清理策略变化时更新。 |

## 当前清理决策

- 已删除空的 `.git.invalid-20260629-193511`。
- 已删除 `Logs/`，此前确认其中只包含本地运行日志，当前崩溃分析不再需要。
- 保留最近烟测生成的 `.tmp\game-smoke.png` 和 `.tmp\game-smoke-new-game.png` 作为当前证据。新游戏截图显示已进入主循环，烟测结果记录了 `NewGameReadyMarker = Controller - Giving Control to Human`。
- 正常修复工作中不要批量删除 `.tmp/`。该目录体积较大，但当前审查或测试文档可能仍引用其中的选定证据路径。
- 暂不删除 `translations/trial-*.json`。这些文件仍记录快速失败尝试，并被审查表导出流程和 `docs/agent/trial-localization-state.json` 引用。
- 最新新增试探批次包括 `translations\\trial-ui-exact-next1-batch.json` 至 `translations\\trial-ui-exact-next8-batch.json`、`translations\\trial-common-placement-failures-1-batch.json`、`translations\\trial-common-property-details-1-batch.json` 至 `translations\\trial-common-property-details-8-batch.json`、`translations\\trial-common-battle-projection-1-batch.json` 至 `translations\\trial-common-battle-projection-2-batch.json`、`translations\\trial-ui-notification-details-1-batch.json`、`translations\\trial-ui-diplomacy-1-batch.json`、`translations\\trial-common-profession-tooltip-1-batch.json`；这些批次均已通过新游戏烟测。剩余 UI 同组候选主要为控件 ID、图标占位、key 后缀、调试 / 错误日志、占位符和外部在线流程，审查导出会按策略标记。
- 已取消 Markdown 审查副本。后续人工审查只使用 `docs/review/known-texts.csv`。

## 2026-07-01 试探性汉化批次补充

- 本轮新增并同步到审查导出的批次：`trial-common-resource-tech-tooltip-1`、`trial-common-clan-structure-tooltip-1`、`trial-common-economy-tooltip-1`、`trial-common-structure-apprentice-1`、`trial-ui-help-tips-1`、`trial-ui-diplomacy-profession-actions-1`、`trial-common-game-abilities-1`、`trial-common-game-description-1`、`trial-common-game-description-retry-1`、`trial-ui-dialog-actions-1`、`trial-ui-dialog-actions-retry-1`、`trial-common-condition-text-1`、`trial-common-condition-text-retry-1`。
- 当前审查表仅保留 `docs/review/known-texts.csv`；`TrialCandidate` 剩余 919 条，唯一持久拒绝项仍是 `ClanCard.AddActionButton` 的 `Leave` 与 UI offset fallback 冲突。

## 2026-07-02 试探性汉化批次补充

- 新增并同步到审查导出的 Common / Game / UI 批次：`trial-common-concepts-help-14` 至 `trial-common-concepts-help-19`、`trial-common-zone-trait-placement-1` 至 `trial-common-zone-trait-placement-2`、`trial-common-map-placement-1` 至 `trial-common-map-placement-2`、`trial-common-config-description-1`、`trial-game-art-hotkeys-1`、`trial-game-static-checks-1` 至 `trial-game-static-checks-2`、`trial-common-command-status-1`、`trial-ui-visible-misc-1`、`trial-ui-tooltip-visible-1`。
- 本轮新增批次中有 150 条输入经新游戏烟测接受，0 条因文本本身被拒绝；其中 `trial-common-map-placement-2` 的 4 条输入、`trial-ui-visible-misc-1` 的 1 条输入和 `trial-ui-tooltip-visible-1` 的 1 条输入已由前序映射覆盖，未重复测试。
- `trial-common-concepts-help-14` 和 `trial-common-concepts-help-15` 暴露了 IL rewrite 输出 DLL 被 Windows 用户映射区域短暂占用的问题；已新增 `Build-IlRewritePatch.ps1` bounded retry 和 `Test-IlRewriteMappedFileRetry.ps1`。
- `trial-common-concepts-help-17` 首轮出现一次已知 `c00000fd` WER 间歇新游戏失败；二分、子批次和 final accepted-only smoke 均通过，因此不作为文本拒绝证据。
- `trial-common-zone-trait-placement-2` 暴露了旧候选来源中的 MethodToken 过期问题：两个 MapUtils 条目误用 `0x06000aca`，最新 DLL catalog 中正确 token 为 `0x06000091`；已在 `trial-common-map-placement-1` 用精确 token 接受，原拒绝证据改名为 `rejected.invalid-catalog-token.json`，不计入不安全文本。
- `trial-ui-tooltip-visible-1` 首轮组合烟测出现一次窗口定位失败，随后二分和 final accepted-only smoke 通过，`rejected.json` 为空；按自动化噪声记录，不作为文本拒绝证据。
- 大量 trial 译文增加字形后触发字体预算失败；已将 Large UI 字体 padding 降为 0，marker 更新为 `merged-fonts-v5-large-ui-pad0`。本轮又发现 Large UI 字符集漏收 `hardcoded-game-il-rewrite.json`，已补入 `Build-Patch.ps1`，最新字体总量 121,271,586 字节，低于 125,829,120 字节预算。旧字体目录删除时出现一次瞬时访问拒绝，已新增 `Build-Patch.ps1` cleanup retry 和 `Test-FontPatchRemovalRetry.ps1`。
- 最新安装烟测已进入主循环，`NewGameReadyMarker = Controller - Giving Control to Human`，`CrashLogUpdated = False`。
- 当前 `docs/review/known-texts.csv` 统计：`AcceptedSmoke` 2514，`TrialCandidate` 665，`Rejected` 1。

## 2026-07-02 试探性汉化批次补充（续）

- 本轮新增并通过新游戏烟测的批次：`trial-ui-visible-misc-2`、`trial-common-sage-effects-1`、`trial-common-visible-misc-1`、`trial-ui-visible-misc-3`、`trial-common-tooltip-visible-2-exact`、`trial-game-static-checks-3`、`trial-game-static-checks-4`。
- 本轮共有 81 条批次输入；其中 79 条新增试探性映射通过 smoke，2 条已被前序映射覆盖，0 条因文本本身被拒绝。
- `trial-common-tooltip-visible-2` 首次失败是 catalog 精度问题：批次使用了审查 CSV 中被规范化的原文，漏掉 `Right-click to spend ` 的末尾空格和 ` and remove this ...` 的开头空格。已改用精确 DLL catalog 值在 `trial-common-tooltip-visible-2-exact` 中通过；该失败不计为不安全文本。

## 2026-07-04 试探性汉化批次补充

- 本轮先将 Game EXE 中明显的内部日志、组件断言、初始化标记和自动化依赖标记从 `NeedsTrial` 改为 `Skipped/TechnicalInternal`，避免把非玩家文本纳入快速失败汉化队列。
- 本轮新增并通过新游戏烟测的批次：`trial-20260704-nongame-needs-1`、`trial-20260704-game-needs-1` 至 `trial-20260704-game-needs-9`。
- 本轮共有 170 条批次输入通过 fast-fail smoke：其中 non-Game 26 条，Game EXE exact-catalog 144 条；0 条因文本本身被拒绝。
- 当前 `docs/review/known-texts.csv` 统计：`Translated` 7123，`NeedsTrial` 252，`Skipped` 10914，`Rejected` 6。剩余 `NeedsTrial` 主要仍是 Game EXE source-position 候选，后续继续从 `docs/review/generated/game-ldstr-catalog.csv` 使用精确 `Value + MethodToken + ILOffset` 分批生成。
- 最终构建、`Test-TextTags.ps1`、`Test-GeneratedTextAliases.ps1`、`Test-FontPatchBudget.ps1`、`Test-OptimizationTooling.ps1`、`Test-KnownTextReviewExport.ps1`、`Test-HoverLocalizationRegressions.ps1` 均通过。
- 最新安装烟测已进入主循环，`NewGameReadyMarker = Controller - Giving Control to Human`，`CrashLogUpdated = False`，安装前已由 `Install-ChinesePatch.ps1` 自动卸载 manifest 管理的旧补丁。
- 当前 `docs/review/known-texts.csv` 统计：总行 6973，已译 4956，未译 2017，已尝试 4967，`AcceptedSmoke` 2653，`TrialCandidate` 599，`Rejected` 1，`SkippedByPolicy` 1407。

## 2026-07-02 试探性汉化批次补充（三）

- 本轮新增并通过新游戏烟测的批次：`trial-common-human-readable-text-1`、`trial-common-property-readable-text-1`、`trial-common-readable-text-2`、`trial-common-readable-text-3`、`trial-game-static-checks-5`、`trial-ui-visible-misc-4`、`trial-common-tostring-labels-1`。
- 本轮共有 87 条批次输入；其中 56 条新增映射通过 smoke，31 条已由既有映射覆盖，0 条因文本本身被拒绝。
- `trial-common-readable-text-2` 首轮组合 smoke 的失败原因为窗口查找失败；随后二分子批和最终 accepted-only smoke 均通过，按自动化噪声记录，不计入不安全文本。
- 最终构建、`Test-TextTags.ps1`、`Test-GeneratedTextAliases.ps1`、`Test-FontPatchBudget.ps1`、`Test-OptimizationTooling.ps1`、`Test-HoverLocalizationRegressions.ps1` 均通过。
- 最新构建报告：字体缓存命中；字体总量 121,273,748 / 125,829,120 字节；`UI IL rewrite` 1339 条、`Common IL rewrite` 796 条、`Game exe IL rewrite` 112 条。
- 最新安装烟测已进入主循环，`NewGameReadyMarker = Controller - Giving Control to Human`，`CrashLogUpdated = False`，`NewGameSmokeSeconds = 22`。
- 当前 `docs/review/known-texts.csv` 统计：总行 7027，已译 5090，未译 1937，已尝试 5101，`AcceptedSmoke` 2735，`TrialCandidate` 519，`Rejected` 1，`SkippedByPolicy` 1407。

## 2026-07-02 试探性汉化批次补充（四）

- 本轮先改进 `tools/Export-KnownTextReview.ps1` 分类：将日志、配置校验、调试 `ToString`、控件 ID、纯格式化标签、`ConvertTags` 匹配 token、日期/季节逻辑和资源路径等 false positive 标为 `SkippedByPolicy`。
- 新增并通过新游戏烟测的批次：`trial-final-visible-fragments-1`。该批次 13 条输入中 11 条新增映射通过 smoke，2 条已由既有映射覆盖，0 条因文本本身被拒绝。
- 目前 `docs/review/known-texts.csv` 中 `TrialCandidate` 为 0；后续新增待试探文本应来自新的静态导出、截图复现或明确重试某类 `SkippedByPolicy`。
- 最终构建、`Test-TextTags.ps1`、`Test-GeneratedTextAliases.ps1`、`Test-FontPatchBudget.ps1`、`Test-OptimizationTooling.ps1`、`Test-HoverLocalizationRegressions.ps1`、`Test-KnownTextReviewExport.ps1` 均通过。
- 最新构建报告：字体缓存命中；字体总量 121,273,748 / 125,829,120 字节；`UI IL rewrite` 1345 条、`Common IL rewrite` 800 条、`Game exe IL rewrite` 113 条。
- 安装流程已自动卸载 manifest 管理的旧补丁再安装新补丁。最终烟测第二次运行进入主循环，`NewGameReadyMarker = Controller - Giving Control to Human`，`CrashLogUpdated = False`，`NewGameSmokeSeconds = 23.03`。第一次复跑停留在主菜单但无崩溃和日志更新，判定为点击 / 焦点自动化噪声。
- 当前 `docs/review/known-texts.csv` 统计：总行 7076，已译 5114，未译 1962，已尝试 5125，`AcceptedSmoke` 2755，`TrialCandidate` 0，`Rejected` 1，`SkippedByPolicy` 1951。
## 2026-07-02 ElfTools 热键提示补丁

- 新增 `translations/hardcoded-elftools-il-rewrite.json`，用于
  `ElfTools.Inputs.Hotkey.BuildTooltip` 的通用二级热键提示；当前只包含
  `This action can be performed by pressing` 与 `on your keyboard.` 两段显示文本。
- `tools/Build-Patch.ps1` 现在会在映射存在时生成 `patch/ElfTools.dll`，
  并在 build report 中记录 `ElfToolsIlRewrite` 与 `ElfToolsDll`。
- `source/ElfTools.original.dll` 属于原始游戏资源，继续受 `.gitignore`
  的 `source/` 规则保护，不上传；缺失时需从本地游戏目录重新提取。
- `docs/review/known-texts.csv` 已重新生成，当前统计为 3528 行，
  3513 行有译文，15 行无译文，3528 行均有尝试状态，3 行为 rejected。

## 2026-07-03 ElfTools 静态发掘与试探批次

- 已对 `source/ElfTools.original.dll` 执行完整 `ldstr` 静态发掘，导出
  811 条记录：388 条 `Technical`、377 条 `Review`、46 条
  `TooltipFragment`。审查导出现在会读取 `.tmp\elftools-ldstr-catalog.csv`，
  并把 ElfTools 未映射候选写入 `docs/review/known-texts.csv`。
- 新增并通过烟测的批次：`translations/trial-elftools-display-tooltips-1-batch.json`。
  该批次包含 8 条 ElfTools 通用显示文本，来源为
  `ElfTools.Gui.CollapsibleContainer.Init`、
  `ElfTools.Gui.Dropdown..ctor` 和
  `ElfTools.Gui.TwoButtonDialog.Initialize`；8 条全部接受，0 条拒绝。
- 本轮把 ElfTools 中其余 394 条审查行标为 `SkippedByPolicy`，原因是
  引擎 / helper 诊断、解析器 token、资源 ID、热键标签或内部异常文本；
  这些不再因“缺少截图证据”跳过，而是按静态来源和风险类别跳过。
- 当前 `docs/review/known-texts.csv` 统计：总行 3928，已译 3519，未译
  409，已尝试 3534，`SkippedByPolicy` 394，`TrialCandidate` 0，
  `Rejected` 3。

## 2026-07-03 审查表生成规则重构

- `tools/Export-KnownTextReview.ps1` 现在默认重建稳定发现缓存，不再依赖 `.tmp` 中可能被清理的临时文件。
- 新增 `docs/review/generated/`，保存审查表生成所需的静态配置候选和 UI/Common/Game/ElfTools `ldstr` 目录。
- `docs/review/known-texts.csv` 现在按源位置输出，不再去重。相同英文出现在多个 XML 节点、DLL 方法或 IL offset 时会分别列出，方便后续按具体位置试探性汉化。
- 当前审查表统计：总行 18125，来源 9 个，已有译文 6731，未译 11394，已尝试 6799，`TrialCandidate` 566，`SkippedByPolicy` 10773，`Rejected` 6。

## 2026-07-03 审查表状态字段精简

- `tools/Export-KnownTextReview.ps1` 现在将人工审查表的旧
  `LocalizationAttempted`、`AttemptStatus`、`FailureReason` 压缩为
  `ReviewState` 和 `ReasonCode`。
- `ReviewState` 只保留五类：`Translated`、`NeedsTrial`、`Skipped`、
  `RecheckedSkipped`、`Rejected`。`Skipped` 用于本轮重审尚未遍历的跳过项，
  `RecheckedSkipped` 用于已重审且仍按策略保留跳过的项。`ReasonCode` 只记录粗粒度原因：
  `TechnicalInternal`、`LogicSensitive`、`FragmentOrToken`、`OutOfScope`、
  `PatchConflict`、`RejectedByTest`。
- 当前审查表统计：总行 18125，来源 9 个，已有译文 6731，未译 11394；
  `ReviewState` 分布为 `Translated` 6780、`NeedsTrial` 566、
  `Skipped` 10773、`Rejected` 6。

## 2026-07-04 试探性汉化批次补充（续）

- 本轮继续使用 Game EXE exact-catalog 快速失败策略，新增并通过新游戏烟测的批次：
  `trial-20260704-game-needs-10` 至 `trial-20260704-game-needs-22`。
- 本轮新增接受 193 条 Game EXE 映射：第 10 至 21 批各 16 条，第 22 批 1 条；
  0 条因文本本身被拒绝。
- 本轮改进 `tools/Export-KnownTextReview.ps1` 分类，将明显内部日志、AI/资源计算
  诊断、`ToString` 调试摘要、无效区域/瘟疫/移动成本断言等 Game EXE false positive
  标为 `Skipped/TechnicalInternal`，避免继续进入试探队列。
- 当前 `docs/review/known-texts.csv` 统计：总行 18488，`Translated` 7510，
  `NeedsTrial` 0，`Skipped` 10972，`Rejected` 6。
- 已通过验证：`Test-TextTags.ps1`、`Test-GeneratedTextAliases.ps1`、
  `Test-KnownTextReviewExport.ps1`。最后一批快速失败烟测进入主循环，
  未产生新的 crash 证据。

## 2026-07-04 跳过文本重审与试探性补译

- 本轮重新审视 `Skipped` 文本，将仍有尝试价值的来源限定为玩家可见概率较高的
  UI/Game 胜利说明、快捷键、通知、商队、氏族界面、命令 tooltip glue 片段，
  以及 Common 属性说明拼接片段。
- 继续跳过的主要类别：日志/诊断/调试文本、资源路径、文件名、解析器结构 token、
  原始 text key、纯标点/格式后缀、派系名/城市名/日期逻辑、外部网页/挑战流程、
  UserSetting 写出注释和明显内部异常文本。跳过理由不再使用“缺少截图证据”。
- 新增并通过新游戏烟测的批次：
  `trial-20260704-retry-skipped-display-1`、`trial-20260704-retry-skipped-display-2`、
  `trial-20260704-retry-skipped-common-desc-1`、
  `trial-20260704-retry-skipped-ui-fragments-1`、
  `trial-20260704-retry-skipped-fragments-2`、
  `trial-20260704-retry-skipped-ui-glue-2`、
  `trial-20260704-retry-skipped-game-glue-1`。
- 本轮新增接受 67 条 IL rewrite 映射，0 条因文本本身被拒绝。
- `trial-20260704-retry-skipped-fragments-2` 首次运行失败是 catalog 精度问题：
  审查 CSV 的 `Original` 列会去除前后空格，而 DLL IL rewrite 必须使用 catalog
  的精确 `Value`。改用 `docs/review/generated/*-ldstr-catalog.json` 中的精确值后，
  同批 13 条一次通过。
- 最新审查导出已覆盖 `docs/review/known-texts.csv`，统计为 18555 行：
  `Translated` 7659，`Skipped` 10890，`RecheckedSkipped` 0，`Rejected` 6。
  用户已要求将先前 `RecheckedSkipped` 全部重置为 `Skipped`，以便
  `GPT-5.3-codex-spark` 在单独对话中按直接运行指南重新筛选并试探性汉化。

## 2026-07-04 Spark 审计与流程加固

- 审计 Spark 直接运行产物时发现 `trial-20260704-spark-recheck-pass2`
  至 `pass4` 把 `AtTheGatesCommon.ns_Text.Text.ConvertTags` 的方括号解析
  token 当作显示文本试探性汉化，其中部分译文已经是乱码。
- 已从 `translations/hardcoded-common-il-rewrite.json` 删除 48 条
  `TrialFastFailSparkRecheck + ConvertTags` 错误映射；保留既有人工审查的
  非 Spark 映射，不扩大回退范围。
- 已把 Spark 留在根目录的临时候选脚本 / CSV 移到
  `.tmp/spark-review-20260704/root-temp-artifacts/`，并把坏批次
  pass2-pass4 移到 `.tmp/spark-review-20260704/unsafe-trial-batches/`。
- 已加固 `tools/Invoke-AtGTrialLocalizationBatch.ps1`：批次入口会拒绝
  `ConvertTags`、方括号-only parser-like token、以及含 U+FFFD 的条目。
  `tools/Test-IlRewriteMapRisk.ps1` 也会在已生成 rewrite map 中拦截同类
  试探性映射。
- 新增 `tools/Test-TrialLocalizationBatchSafety.ps1`，并将其写入
  Spark 指南和 package/install 工作流。
- 最新审查导出统计：总行 18597，`Translated` 7752，
  `TranslatedStateRows` 7801，`Skipped` 10788，`Rejected` 8，
  `NeedsTrial` 0。
- 本轮验证已通过：`Build-Patch.ps1`、`Test-TrialLocalizationBatchSafety.ps1`、
  `Test-IlRewriteMapRisk.ps1`、`Test-KnownTextReviewExport.ps1`、
  `Test-HoverLocalizationRegressions.ps1`、`Test-TextTags.ps1`、
  `Test-GeneratedTextAliases.ps1`、`Test-FontPatchBudget.ps1`、
  `Test-OptimizationTooling.ps1`、`Test-IlRewriteMappedFileRetry.ps1`。
  安装刷新后默认 `Test-GameLaunch.ps1` 到主菜单通过，未进入随机新游戏。
