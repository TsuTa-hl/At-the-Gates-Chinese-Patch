# At the Gates 简体中文补丁工程

本工程构建 Jon Shafer's *At the Gates* 的非官方简体中文补丁，不包含任何原版游戏文件。

玩家只需使用发布分支或发布包中的 `README.md`、安装脚本、卸载脚本和 `patch/`；开发工程的工具、源目录和说明不随发布包分发。

## 开发基线

构建、烟测和发布均以 Steam 当前原版为基线。先从已恢复原版的游戏目录提取开发输入：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Initialize-AtGSource.ps1 -GamePath 'D:\SteamLibrary\steamapps\common\Jon Shafer''s At the Gates' -Refresh
```

然后运行本地统一门禁：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGVerification.ps1 -GamePath 'D:\SteamLibrary\steamapps\common\Jon Shafer''s At the Gates'
```

门禁会重建补丁、执行锁定依赖下的 `dotnet test`、验证发布包的假游戏安装卸载、安装到指定 AtG 目录并做主菜单烟测。默认不执行黑盒场景。`-StaticOnly` 是唯一明确跳过真实烟测的模式；成功后仍保留已安装补丁。

## 安装行为

安装器只确认目标目录同时含有 `At The Gates.exe` 和 `Content\Text\English.xml`，不校验 Steam 版本、文件指纹或 SHA-256，因此可用于玩家改动过的目录和 MOD 环境。

对补丁覆盖的文件，安装器会在覆盖前记录并备份当前实际内容。卸载会逐项恢复该备份；安装前不存在的补丁专有文件才会被删除。重叠 MOD 内容会在安装期间暂时被覆盖，卸载后会按字节恢复。无关 MOD 文件不会被触碰。

## 发布

仅从干净且与 `origin/main` 完全同步的 `main` 运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Publish-AtGRelease.ps1 -GamePath 'D:\SteamLibrary\steamapps\common\Jon Shafer''s At the Gates'
```

该命令运行完整门禁，生成自包含的玩家包，并以独立最小历史通过 `--force-with-lease` 更新 `codex/release-chinese-patch`。

详细路由见 [AGENTS.md](AGENTS.md) 和 [知识索引](docs/agent/knowledge-index.md)。
