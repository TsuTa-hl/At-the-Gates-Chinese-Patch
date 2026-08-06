# 《At the Gates》简体中文补丁

这是《At the Gates》的非官方、免费简体中文补丁。补丁不包含任何原始游戏文件；请先安装正版游戏。

## 使用方法

1. 退出游戏。
2. 解压本发布包到任意文件夹。
3. 在该文件夹中右键使用 PowerShell 运行：

~~~powershell
powershell -ExecutionPolicy Bypass -File .\Install-ChinesePatch.ps1
~~~

4. 脚本会自动寻找 Steam 游戏目录。若未找到，请指定游戏目录：

~~~powershell
powershell -ExecutionPolicy Bypass -File .\Install-ChinesePatch.ps1 -GamePath 'D:\SteamLibrary\steamapps\common\Jon Shafer''s At the Gates'
~~~

安装时，脚本会先备份将被替换的原始文件；再次安装会自动刷新旧版本补丁。

## 卸载

退出游戏后运行：

~~~powershell
powershell -ExecutionPolicy Bypass -File .\Uninstall-ChinesePatch.ps1
~~~

卸载脚本会从备份逐项恢复原始文件、删除补丁专有文件，并在每一步核验结果。为避免原版游戏读取中文存档名时崩溃，它可能将存档文件名改为 ASCII 字符；不会修改存档内容。

## 说明与反馈

- 本补丁仅供非商业用途，且不代表或隶属于 Conifer Games。
- 修改后的游戏问题请提交到本项目，而不要向 Conifer Games 寻求补丁支持：<https://github.com/TsuTa-hl/At-the-Gates-Chinese-Patch/issues>
- 发布许可基于善意授予，可能被撤销。
