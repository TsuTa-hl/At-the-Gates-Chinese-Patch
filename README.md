# Jon Shafer's At the Gates 简体中文补丁

## 开发者说明

这是我用codex为独立游戏Jon Shafer's At the Gates制作的汉化补丁，本体见：
https://store.steampowered.com/app/241000/Jon_Shafers_At_the_Gates/

安装方式1：运行Install-ChinesePatch.ps1
安装方式2：将patch路径下的文件覆盖到\steamapps\common\Jon Shafer's At the Gates

本体2020年以较低的完成度停止更新，特色为人口-职业机制，类似Jon Shafer在Firaxis作为original prototype参与的Sid Meier's Civilization 4 Colonization。

## AI说明

这是一个本地补丁工程。脚本默认按以下顺序定位游戏目录：

1. 命令行参数 `-GamePath`
2. 环境变量 `ATG_GAME_PATH` 或 `AT_THE_GATES_PATH`
3. Steam 注册表和 `steamapps\libraryfolders.vdf`

如果自动定位失败，先设置环境变量：

```powershell
$env:ATG_GAME_PATH = "D:\SteamLibrary\steamapps\common\Jon Shafer's At the Gates"
```

## 使用

1. 构建补丁：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\Build-Patch.ps1
   ```

   当前翻译已经补齐，不需要运行外部翻译脚本。若后续游戏更新新增英文文本，且确实需要外部翻译服务时，必须显式批准：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\Complete-Translations.ps1 -UseExternalTranslation
   ```

   该命令会把未翻译的游戏文本发送到公共翻译端点；不同意外发文本时不要运行。

2. 安装补丁：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Install-ChinesePatch.ps1
   ```

3. 卸载补丁：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Uninstall-ChinesePatch.ps1
   ```

4. 启动烟测：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\Test-GameLaunch.ps1
   ```

   这个脚本会启动游戏、等待窗口、保存一张截图、检查是否生成新的 `Crash.AtGLog`，然后关闭测试窗口。

安装时会先备份被覆盖的原文件，备份位于游戏目录的 `_ChinesePatchBackup` 文件夹。

## 翻译维护

- 原始文本：`source\English.original.xml`
- 翻译表：`translations\zh-CN.json`
- 硬编码 UI 文本：`translations\hardcoded-strings.json`
- 硬编码通用界面文本：`translations\hardcoded-common-strings.json`
- 实验性 Common 概念偏移文本：`translations\hardcoded-common-offsets.json`
- 配置节点文本：`translations\config-node-strings.json`
- 配置节点补充文本：`translations\config-node-extra-strings.json`
- 静态文本候选导出：`tools\Export-StaticTextCandidates.ps1`
- 生成结果：`patch\Content\Text\English.xml`
- 当前 XML 覆盖：1422 / 1422 条文本。剩余文本已使用 ChatGPT 在本地会话中补译，并对已翻译文本中的可见英文标签做了校对；未调用外部翻译服务。
- 当前 DLL 硬编码覆盖：121 条 `AtTheGatesUI.dll` 文本，另有 1 条 `AtTheGatesCommon.dll` 默认按钮文本。另通过节点级配置补丁覆盖 106 条 `ClanTraits.xml` 特质名，以及 231 条特质对话/描述。DLL 替换均为可安全等长替换；配置补丁只按 ID、XPath 和索引修改显示节点，不改 ID 或逻辑引用。
- 字体补丁：构建脚本会从 `source\fonts-original` 读取原始 XNA SpriteFont，保留原 glyph 和图标，再追加中文字符。安装脚本只会默认安装带 `.atg-merged-fonts` 标记的合并字体；旧的纯中文生成字体会被跳过，以避免游戏图标变成乱码。
- 静态文本排查：运行 `tools\Export-StaticTextCandidates.ps1` 会把配置 XML 中可能显示的文本导出到 `.tmp\static-text-candidates.json` 和 `.tmp\static-text-candidates.csv`，并按安全性、是否需要字体、是否需要排版复核分类。
- 风险说明：`AtTheGatesCommon.dll` 的概念术语表同时参与 UI 显示和逻辑初始化。默认不会启用 `translations\hardcoded-common-offsets.json`；只有显式传入 `Build-Patch.ps1 -PatchCommonConceptTerms` 才会应用，该路径当前仅保留作实验，不建议安装测试版使用。可见通知里的 `Clan <Name>` 前缀和日期横幅仍归类为逻辑敏感/需继续定位项，不在默认补丁里强改。

游戏当前只有 `Content\Text\English.xml` 这一个语言入口，所以补丁会生成同名文件覆盖原英文文件。
注意：游戏自带 XML 解析器不接受 `<?xml ...?>` 声明，生成的 `English.xml` 必须直接以 `<english>` 开头。

`AtTheGatesUI.dll` 和 `AtTheGatesCommon.dll` 中的硬编码文本通过 UTF-16 完整字符串边界替换生成，替换后的字符串必须不长于原字符串。构建字体时会自动把硬编码映射的中文文本加入字符集，避免主菜单等硬编码文本缺字。
