# 工作流：发布玩家发行分支

只能从与 `origin/main` 完全一致的干净本地 `main` 运行此工作流。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Publish-AtGRelease.ps1 -GamePath '<Steam AtG original>'
```

该命令会显式调用 `Release` 验证档位：运行完整静态套件、全目录目录与界面审计、模拟发布包和事务回归，然后执行真实的事务安装及主菜单烟测。仅限发布的事务夹具要求 AtG 进程已停止。随后，它会导出自包含包、验证严格白名单、创建一条独立的发行提交（其提交信息记录源 `main` SHA 与补丁数量），并以 `--force-with-lease` 推送到 `codex/release-chinese-patch`。

不要为普通的玩家可见汉化修复调用 `Release`；日常工作使用 `package-and-install.md` 中的 `Localization` 档位。

发布树仅包含：

- `README.md`
- `Install-ChinesePatch.ps1`
- `Uninstall-ChinesePatch.ps1`
- `patch/`

若租约失败，不要使用普通强制推送。检查新的远程发行头、同步 `main`、重新运行门禁，然后再次发布。
