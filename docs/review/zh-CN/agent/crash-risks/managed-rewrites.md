# 托管重写与逻辑风险

修改任意托管 DLL/EXE 重写、富文本概念行为或逻辑敏感显示术语时阅读本文件。

## Common 与概念术语

- 默认禁用 `translations\hardcoded-common-offsets.json` 与
  `Build-Patch.ps1 -PatchCommonConceptTerms`。
- 宽泛 Common 概念替换（包括直接替换 `Turn`）即使字节精确也曾导致启动失败。
- 如 `Cannot Learn Right Now` 等短语，保留概念标识符，通过
  `hardcoded-common-il-rewrite.json` 中范围化的 dnlib 显示重写处理；不要改原始
  概念 ID 或宽泛元数据偏移。

## UI DLL

- 首选 `Build-IlRewritePatch.ps1`：dnlib 按 `MethodToken + ILOffset + Original`
  重写 `ldstr`，避免填充。
- 经 `.tools\dotnet\dotnet.exe` 将重写器作为 `AtG.IlRewrite.dll` 运行。不要运行
  `AtG.IlRewrite.exe`；没有全局 .NET 运行时的系统可能显示应用程序错误对话框。
  `UseAppHost` 保持 false。
- 旧 `Build-IlStringPatch.ps1` 的 `#US` 回退只能写入适合原始堆条目的译文。
- `Text.HumanReadableMod`（`0x06000207`）只有一项获批准的结构显示操作：动态 `x`
  后缀（`IL_0164`）处的 `HumanReadableModDynamicPercent`。来源参数已是整数百分比；
  该操作只移除小数倍率格式并在追加 `%` 前保留原值。必须限于该方法和锚点，不能推广
  到任意数字字符串。
- 每个迁移字符串在具备构建、安装、烟测与目标 UI 覆盖前保留字节/偏移回退。已验证的
  偏移回退仍期待原文时，不能重写 `ClanCard.AddActionButton` 的 `Leave `。

## Game 与 ElfTools

- Game EXE 重写仅限操作按钮提示中的静态资源要求等仅显示 `ldstr` 片段。每条新记录
  都需要固定存档加载、目标 UI 覆盖和烟测。
- ElfTools 重写仅限热键提示、可折叠容器、下拉框、双按钮对话框等显示助手。不得宽泛
  重写输入处理、解析器胶水、诊断、资源 ID 或引擎助手。

## 逻辑敏感文本

派系名、日期横幅术语、`Clan <Name>` 通知前缀和 Common 概念术语都不适合批量替换。
只能采用小而隔离的编辑，并经过构建、安装、启动与目标 UI 回归；导航或启动失败时
立即回滚。

知识倒计时是方法范围 Common 重写，而非全局 `in` 替换；可见职业卡的连接词、Innate
和 Trait 片段也只在各自已证明的显示路径处理。选择新游戏部族后的崩溃证明
`Screen_ChooseFaction.Update` 会从按钮文本前四字符推导派系键，因此十个可玩派系的
`<name>` 和 `city/name` 配置值必须保留原始逻辑字符串；可见中文由运行时显示映射提供。

## 事务恢复与字节码完整性

- 安装架构会在首次复制前备份并哈希生成补丁树的每个文件，写入 Prepared 清单、验证
  已安装哈希后才标记 Installed。卸载合并清单、原始备份树和已知运行时专有产物，逐项
  验证恢复或移除成功后才删除清单。
- 安装或烟测前，已安装状态必须哈希检查每个当前清单目标。缺少备份只在每条记录均为
  Restored 且与安装前字节一致（或补丁专有文件不存在）时可接受；任何模糊缺失备份都
  是硬失败。
- Windows 的短暂映射文件锁通过 `Copy-AtGFileIfChanged` 的有界重试处理。绝不对锁定
  XML 或 DLL 强制填充或部分就地写入；应保留可恢复事务，直到可逐字节恢复和验证。
- 动态百分比重写必须保留 `String.Concat` 所需的栈接收者；构建应在锚点前不再存在
  `ldarg.1` 时失败。静态 IL 与最终安装 DLL 哈希均是结构操作的必要证据。

历史的具体界面修复、次数和人工验证状态不在本审查副本中展开；原始风险记录和当前
任务交接保留完整证据。
