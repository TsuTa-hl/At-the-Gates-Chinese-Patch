# 工程清单

本文件只描述当前工程结构、生成物和保留边界。历史试验、逐日流水与截图证据由 Git、
结构化状态和清理交接承担。

| 位置 | 用途 | 保留规则 |
| --- | --- | --- |
| `source/` | 原始游戏文件与提取副本。 | 不直接修改。 |
| `translations/` | 可编辑翻译、精确重写和组合规则。 | `composite-text-rules.json` 是组合规则事实来源；`concept-key-translations.json` 是概念键显示词的静态索引。 |
| `patch/` | 可再生补丁产物。 | 由构建生成，不作为手工编辑源。 |
| `tools/` | PowerShell 5.1 兼容入口与 .NET 工具。 | 公开脚本保持 5.1 兼容。 |
| `tools/AtG.*` | Core、CLI、ManagedRewrite、RuntimeText、TestHarness 工具项目。 | 复杂逻辑优先放入 .NET 工具。 |
| `tools/Export-ConceptKeyTranslations.ps1` | 概念键显示词静态索引生成器。 | 从原始/补丁 XML 和组合规则重建 `concept-key-translations.json`。 |
| `docs/agent/` | 工作流、索引和专题知识。 | 从 `knowledge-index.md` 按需读取。 |
| `docs/review/generated/` | 生成的 DLL/XML 目录快照。 | 供刷新诊断与用户审查参考；AI 的操作数直接来自 SQLite。 |
| `docs/review/Generate-ReviewViews.ps1` | 三类按需生成视图的入口。 | 用户自行运行，`KnownTexts`、`Composite`、`Todo` 默认只输出到 `.tmp/review-views/`，不保留在文档目录。 |
| `.cache/atg-catalog.sqlite` | 文本出现位置、语义组、绑定、精确原文与定位器主库。 | AI 通过 catalog 工具直接查询和维护；不经过导出中间数据。 |
| `.tmp/` | 可再生运行证据、临时构建和测试输出。 | 每项任务先文本化交接，再按清理工作流筛除。 |

## 当前渲染与补丁边界

- 默认使用 `DynamicCjk`：原 SpriteFont 继续绘制拉丁、数字和图标；
  `AtG.RuntimeText.dll` 与随补丁分发的 Noto Sans SC 绘制 CJK。
- `MergedFonts` 仅是一个发布周期的回滚路径，不能恢复旧的全语料 SpriteFont 方案。
- `English.xml` 无 XML 声明；ClanCard 中文别名目录、资源复数别名和富文本概念键都
  是构建/回归必须保护的结构。
- Common 概念词、派系名、日期和生成名称保持逻辑敏感，除非有隔离的目标回归证明
  安全。
