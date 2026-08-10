# 启动与内容风险

修改 XML 输出、启动行为、设置描述、宗教配置或 ClanCard 资产时阅读本文件。

## XML 与启动

- `English.xml` 不能有 XML 声明。`Build-ChineseXml.ps1` 保持
  `OmitXmlDeclaration = true`；生成文件必须以 `<english>` 开始。
- 静默退出可能绕过崩溃对话框且不改变 `Crash.AtGLog`。此时将
  `At The Gates.exe` 的 Windows Application/.NET Runtime 事件视为权威证据。
  随机新游戏生成期间孤立的 `c00000fd` WER，只有同一补丁构建随后通过重复烟测时
  才可重试。
- 不得通过会将其写为 `Settings\Settings.xml` 注释的路径翻译 `UserSetting_*` 描述或
  警告字符串。非 ASCII 注释会使该文件无效。`Test-GameLaunch.ps1` 返回的
  `SettingsErrorSeen=True` 是烟测失败。

## 启动环境

不把游戏目录设为工作目录而启动 `At The Gates.exe`，可能在
`AtTheGatesCommon.ns_GlobalSystems.Log` 失败。使用
[../operations/game-automation.md](../operations/game-automation.md) 的启动流程。

## ClanCard 资产别名

翻译后的纪律名可能成为 ClanCard 资产路径组件，例如
`Images\Interface\ScreenSpecific\ClanCard\冶金\PortraitBackground_2`。

- 在 `tools\Build-Patch.ps1` 中保留中文别名复制逻辑。
- 保留 `农耕`、`冶金`、`工艺`、`探索`、`畜牧`、`荣誉` 的生成别名。
- 删除别名会因缺少 `PortraitBackground_*.xnb` 而崩溃氏族界面。
- PowerShell 5.1 在 ANSI 回退下不能依赖原始中文路径字面量。应从 Unicode 码点或
  生成的别名列表推导组件，并验证最终 `Test-Path` 结果。

## 宗教配置

- 宗教 `name` 和 `adjective` 只有通过稳定宗教 ID 打补丁时才显示安全。除非专用来源/
  UI 回归证明安全，否则保留 `RELIGION_*` ID 和描述占位符不变。
- 固定存档宗教界面已在 `DynamicCjk` 下以中文宗教名打开；不要重新引入合并字体依赖。
