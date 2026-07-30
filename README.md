# Jon Shafer's At the Gates 简体中文补丁

这是为 **Jon Shafer's At the Gates** 制作的简体中文补丁工程。项目以启动稳定性和精确、可回归的本地化为优先级；它不是官方产品，也不包含游戏本体。

> **非官方、玩家制作的免费补丁；仅限非商业用途。**

游戏页面：[Steam 商店](https://store.steampowered.com/app/241000/Jon_Shafers_At_the_Gates/)

## 授权、发布与支持声明

Jon Shafer 已许可本项目发布和推广本补丁，条件如下：

- 本补丁始终免费且严格限于非商业用途，并在下载和宣传中明确标注为非官方玩家作品。
- 发布物不包含、也不重新分发任何原版游戏文件；使用者必须拥有合法的《At the Gates》游戏副本。
- Conifer Games 不为已安装本补丁的游戏提供技术支持。补丁环境下的崩溃报告和技术问题请提交至[本项目 Issues](https://github.com/TsuTa-hl/At-the-Gates-Chinese-Patch/issues)，不要提交给 Conifer Games。
- 该许可基于善意授予，且可撤销。

## 当前能力

- XML、配置节点、运行时显示文本与经过精确定位的托管程序集文本汉化。
- `DynamicCjk` 运行时中文渲染、字形缓存与预热机制，保留原有拉丁字符和图标绘制路径。
- 组合/富文本规则集中保存在 `translations/composite-text-rules.json`，保护概念键、占位符、热键、颜色与递归悬浮结构。
- SQLite 文本目录与静态审查工具，用于定位来源、验证规则和生成待办。
- 补丁构建、安装、启动烟测及面向风险点的静态测试工具。

## 使用要求

- Windows PowerShell 5.1。
- 已安装的游戏副本。脚本按以下顺序定位游戏目录：`-GamePath`、环境变量 `ATG_GAME_PATH` / `AT_THE_GATES_PATH`、Steam 注册表与库目录。
- 如果自动定位失败，可设置：

```powershell
$env:ATG_GAME_PATH = "D:\SteamLibrary\steamapps\common\Jon Shafer's At the Gates"
```

## 快速开始

1. 构建补丁：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\Build-Patch.ps1
   ```

2. 安装补丁：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Install-ChinesePatch.ps1
   ```

3. 运行启动烟测：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\tools\Test-GameLaunch.ps1
   ```

   此命令会启动游戏、等待窗口、保存测试截图并检查新的 `Crash.AtGLog`，随后关闭测试进程。

4. 卸载补丁：

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\Uninstall-ChinesePatch.ps1
   ```

安装过程会把被覆盖的原文件备份到游戏目录的 `_ChinesePatchBackup`。

## 开发与本地化

| 位置 | 用途 |
| --- | --- |
| `source/` | 原始游戏文件与只读提取副本；不直接编辑。 |
| `translations/` | 可编辑翻译、精确重写映射、组合与运行时显示规则。 |
| `tools/` | PowerShell 入口与 .NET 构建、定位、验证工具。 |
| `patch/` | 可再生成的补丁产物。 |
| `.cache/atg-catalog.sqlite` | 已发现文本、语义组、翻译绑定与证据目录。 |

对于截图中发现的英文、原始键或乱码，先查询 SQLite 目录；对 DLL 修改始终使用精确的 `MethodToken + ILOffset + Original` 证据。不要将归一化后的审查文本作为 IL 操作数。

### 临时审查视图

```powershell
powershell -ExecutionPolicy Bypass -File .\docs\review\Generate-ReviewViews.ps1 -View All
```

该命令仅在 `.tmp\review-views` 生成三个可丢弃的 CSV：

- `known-texts.csv`：直接读取 SQLite 目录。
- `composite-text-localization.csv`：直接读取组合规则 JSON，包含 `RowKind=Entry` 和 `RowKind=Rule`。
- `localization-todolist.csv`：直接读取 SQLite 与组合规则 JSON；不会读取前两个视图。

这些 CSV 不是源数据，也不应提交为永久文档。

## 安全原则

- 先做显示路径定位，再做最小化修改；逻辑敏感名称、日期、标识符和枚举默认不改。
- 保留 XML ID、XPath 身份、富文本标签、概念键、占位符、热键和颜色结构。
- `#US` 堆文本不得扩容；无法安全替换时应失败，而不是覆盖相邻元数据。
- 仅在明确批准时使用外部翻译服务：

  ```powershell
  powershell -ExecutionPolicy Bypass -File .\tools\Complete-Translations.ps1 -UseExternalTranslation
  ```

  该命令会将未翻译文本发送到外部服务；未获批准时不要运行。

更多工作流、构建边界与测试规则见 [AGENTS.md](AGENTS.md) 和 [docs/agent/knowledge-index.md](docs/agent/knowledge-index.md)。
