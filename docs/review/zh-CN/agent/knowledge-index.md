# 知识路由索引

在 `AGENTS.md` 之后使用本索引。读取所选工作流的必读文件，再只读取按条件路由
的专题。SQLite 与规则 JSON 是事实来源；用户审查导出不是 AI 工作流输入。

## 工作流路由

| 工作流 | 始终读取 | 仅在需要时读取 |
| --- | --- | --- |
| 清理 | `operations.md` | 固定存档或测试运行可能受保护时读取 `black-box-tests.md` |
| 评估/修复 | `text-sources.md`、`translation-style.md` | 可见文本读 `catalog-review.md`；XML/DLL 读 `managed-patching.md`；UI 映射读 `ui-source-map.md`；动态文本按 `EntryPointId`/`RuleId` 查询组合规则 JSON；按症状读取崩溃风险、黑盒接口与自动化；已拒绝操作数读安全注册表 |
| 打包/安装 | `operations/build-and-install.md`、`architecture.md` | 文本生成或重写后读文本/托管专题；动态/富文本变更后读组合规则 JSON；读取与变更子系统对应的崩溃风险专题 |
| 发布分支 | `workflows/publish-release-branch.md`、`operations/build-and-install.md` | 安装器、卸载器或补丁产物变更后读 `architecture.md`、`crash-risks.md` |
| 测试/循环 | `black-box-tests.md`、选定接口专题、`operations/game-automation.md` | 只有出现匹配失败症状才读 text/catalog/composite/style/crash 专题 |
| 更新知识 | 本索引和变更文件清单 | 仅测试结果时读最新测试交接；读取受变更事实影响的所有者文件 |

## 专题归属

| 关注点 | 所有者 |
| --- | --- |
| PowerShell 5.1、引号、路径、工作目录、坐标含义 | `operations.md` |
| 构建/安装/烟测 | `operations/build-and-install.md` |
| 源/构建/事务/发布数据流 | `architecture.md` |
| 仓库级重构验证及范围限制 | `current-status.md` |
| 恢复和常见操作故障 | `troubleshooting.md` |
| 输入、截图、崩溃流程 | `operations/game-automation.md` |
| 资源/网络/运行时诊断 | `operations/diagnostics.md` |
| 来源优先级和安全性 | `text-sources.md` |
| Catalog 操作和用户审查导出 | `text-sources/catalog-review.md` |
| XML/DLL/标签精度 | `text-sources/managed-patching.md` |
| UI 来源路由 | `text-sources/ui-source-map.md` |
| 已退役批次的安全决定 | `text-sources/localization-safety.md` 和 `translations/localization-safety-registry.json` |
| 组合规则 | `translations/composite-text-rules.json`；直接查询 `EntryPointId` 和 `RuleId` |
| 概念链接显示词 | `translations/concept-key-translations.json`；直接查询 `Key` |
| 测试策略/状态 | `black-box-tests.md` |
| 接口覆盖 | `black-box/interfaces.md` 和 `black-box-scenarios.json` |
| 翻译措辞 | `translation-style.md` |
| 崩溃和回滚索引 | `crash-risks.md` |
| 启动/XML/设置/宗教/ClanCard 细节 | `crash-risks/startup-and-content.md` |
| 运行时字体、图集、图标、重载/OOM 细节 | `crash-risks/runtime-and-assets.md` |
| 托管重写和逻辑敏感细节 | `crash-risks/managed-rewrites.md` |

## 生成的权威数据

- `.cache/atg-catalog.sqlite`：精确出现位置、绑定、源路径和定位器的 AI catalog
  权威数据。通过 catalog 工具查询和维护；不要将用户审查导出作为中间表示。
- `translations/composite-text-rules.json`：可编辑的组合规则权威数据。
- `translations/concept-key-translations.json`：含源显示词和已观察中文显示词的静态
  概念链接索引。静态输入变更后用 `tools/Export-ConceptKeyTranslations.ps1` 重建；
  编辑概念链接显示词前直接查询 `Key`。
- `docs/review/Generate-ReviewViews.ps1`：用户自行运行的导出工具，在
  `.tmp/review-views` 下生成临时 `KnownTexts`、`Composite`、`Todo` 视图。AI 维护
  脚本，但绝不生成或读取其输出。
- `docs/agent/black-box-scenarios.json`：坐标与场景权威数据。
- `docs/agent/clan-trait-verification.json`：特质验证状态。
- `docs/agent/terrain-tooltip-boundary.json`：源派生的地形/资源点/资源边界与运行时
  可达性状态；用 `tools/Build-TerrainTooltipBoundary.ps1` 刷新，绝不可作为翻译
  操作数。
- `docs/agent/interface-localization-routes.json`：静态进度审计的确定性接口/界面/
  条件路由。
- `docs/agent/interface-localization-progress.md`：进度公式、隔离导出协议和最新静态
  基线。
