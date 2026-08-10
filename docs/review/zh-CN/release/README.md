# At the Gates 简体中文补丁

这是 Jon Shafer's *At the Gates* 的非官方、免费、非商业简体中文补丁。补丁不
包含原版游戏文件；请先安装合法拥有的游戏副本。

## 安装

1. 退出游戏。
2. 解压本发布包。
3. 在该目录运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ChinesePatch.ps1
```

脚本会自动查找 Steam 游戏目录。若未找到，请明确指定：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Install-ChinesePatch.ps1 -GamePath 'D:\SteamLibrary\steamapps\common\Jon Shafer''s At the Gates'
```

安装器只确认目录包含 `At The Gates.exe` 与 `Content\Text\English.xml`，不会
检查游戏版本或文件指纹。因此它可以安装到玩家修改过或装有 MOD 的 AtG 目录。

安装前，脚本会备份每一个将被覆盖的实际文件到游戏目录中的
`_ChinesePatchBackup`，并写入事务清单。若补丁与 MOD 覆盖同一路径，MOD 文件会
在安装期间被暂时覆盖；卸载后会按字节恢复。无关 MOD 文件不会被修改。

## 卸载

退出游戏后运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\Uninstall-ChinesePatch.ps1
```

卸载会逐项验证并恢复安装前的备份。只有安装前不存在的补丁专有文件会被删除。
若某个补丁专有文件在安装后被其他工具修改，脚本会停止并保留清单与备份，避免
误删玩家内容。

## 说明与反馈

- 本补丁为玩家作品，非官方产品；Conifer Games 不提供补丁环境支持。
- 请将补丁相关问题提交到本项目的 GitHub Issues。
- 仅限非商业使用；发布授权基于善意授予，可能被撤回。
