# 文本来源安全性和优先级

用此路由索引选择精确的显示来源。它不是实验记录，也不能替代源 catalog。

## 来源优先级

1. `source/English.original.xml` → `translations/zh-CN.json` → 生成的
   `patch/Content/Text/English.xml`
2. 稳定配置 XML 节点 → 以 ID/XPath 为范围的 config-node 映射
3. UI 显示 `ldstr` → 精确 UI IL 重写（`MethodToken + ILOffset + Original`）
4. 最终运行时显示 → `translations/runtime-display-strings.json`
5. 仅当结构化路径无法覆盖同一可见文本时，才使用已验证的字节/偏移回退

对于组合、动态或富文本，先读取 `translations/composite-text-rules.json` 并保留
其 `EntryPointId`、`RuleId`、标签、占位符、热键、概念键、颜色和递归悬浮结构。

## 安全类别

- `DisplaySafe`：有精确路径的隔离玩家可见文本。
- `DisplayComposite`：构建完整模板或最终显示规则；绝不全局替换脱离上下文的语法
  片段。
- `LogicSensitive`：名称、日期、标识符、序列化或与行为耦合的文本；需要隔离回归
  证据。
- `Technical`：诊断、路径、解析器胶水、元数据和非显示文本。

## 稳定规则

- `English.xml` 以 `<english>` 开始，且没有 XML 声明。
- 保留 XML ID、XPath 身份、概念键、原始标签和占位符。
- 现有存档可能带有旧显示名；优先使用运行时显示映射，不要更改面向逻辑的标识符。
- `UserSetting_*` 描述不是托管字符串补丁目标：其序列化的非 ASCII 注释可能破坏
  `Settings.xml`。
- 不得将用户审查导出用作 IL 操作数。直接查询 `.cache/atg-catalog.sqlite` 并保留
  catalog 返回的精确 `Original`、`SourceFile` 与 `Locators` 值。

## 条件专题

- 直接 catalog 操作与用户审查导出：[catalog-review.md](text-sources/catalog-review.md)
- XML/DLL/标签精度：[managed-patching.md](text-sources/managed-patching.md)
- UI 界面路由：[ui-source-map.md](text-sources/ui-source-map.md)
- 已退役批次的规范决定：[localization-safety.md](text-sources/localization-safety.md)
  与 `translations/localization-safety-registry.json`

不要为单一资源、屏幕、事件、字符串或事故创建条件专题。精确来源查询 SQLite，
任务专属证据保留在当前交接中；只有可跨多个未来任务复用的规则、模式或路由决定
才写入文档。
