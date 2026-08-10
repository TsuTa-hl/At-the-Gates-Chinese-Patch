# Catalog 操作与用户审查导出

SQLite catalog 是在截图中发现英文、原始键、乱码和标签时的首要查询入口。先通过
catalog 工具查询，再直接搜索源文件。AI 操作数必须使用 SQLite 返回的精确
`Original`、`SourceFile` 和 `Locators` 字段；AI 不得生成或读取用户审查导出。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Invoke-AtGPatchCli.ps1 -Command catalog -CatalogAction search -CatalogText '<visible text>' -CatalogLimit 20
```

已知来源时添加 `-CatalogSource '<assembly or path>'`。编辑 DLL 时，使用精确的
SQLite 操作数；绝不经由用户审查导出。

权威数据：

- `.cache/atg-catalog.sqlite`：本地出现位置、分组、绑定、精确源和定位器数据库；
  是 AI 的查询与维护界面。
- `translations/composite-text-rules.json`：持久的组合显示绑定。
- `docs/review/Generate-ReviewViews.ps1`：由用户运行的 `KnownTexts`、
  `Composite` 和 `Todo` 导出器，输出到 `.tmp`；AI 维护此脚本，但不生成或读取其视图。

每个字面 Composite 引用都只能带一个持久来源定位器：托管
`MethodToken + ILOffset`、完整 XML XPath、英文文本键、配置
`ID + XPath + Index`，或运行时映射的 section/original/key。未解析的定位器必须明确
保留，不能依据相似方法或字符串猜测。

来源映射或组合规则变更后，仅在源数据变化时刷新 SQLite catalog，并运行由 xUnit
拥有的静态检查。用户生成的审查导出不能取代已安装本地化变更的真实主菜单烟测。
