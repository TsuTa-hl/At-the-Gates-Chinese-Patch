# 接口本地化进度审计

这是静态来源与条目审计，不是 UI 覆盖。使用以下命令生成新的隔离报告：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-InterfaceLocalizationProgress.ps1
```

导出器会在 `.tmp` 下写入可丢弃的 summary/items/metadata 文件。除非明确请求私有
快照，否则它会重建 KnownText 数据。

`VisibleLocalizationRate` 统计具有非空中文翻译和精确定位器的可见可翻译源条目。
`AllKnownTrackingRate` 统计每个已知条目是否有明确路由；技术、结构、已拒绝、语言
中性和未分类条目仍分别可见。

仅当生成构建报告的输入摘要与当前源映射一致时，`BuildArtifactState=Current` 才成立。
缺失或旧版报告绝不能视为当前输出。

使用当前生成 metadata 作为基线。不要把带日期的总数或纯静态结果复制到本文档；
实际烟测或黑盒状态记录在所属场景和 current-status 记录中。
