# 工作流：评估与修复

## 目的

诊断并修复本地化、崩溃、布局、暴露键和安全显示问题。先完成任务清理，并复用其
交接。

## 首先读取

- `docs/agent/knowledge-index.md`
- `docs/agent/text-sources.md`
- `docs/agent/translation-style.md`

## 按症状读取

| 症状或变更 | 还要读取 |
| --- | --- |
| 可见英文、原始键、乱码、未知来源 | `text-sources/catalog-review.md` |
| XML、DLL、IL、标签、概念或回退补丁 | `text-sources/managed-patching.md` |
| 已知 UI 界面 | `text-sources/ui-source-map.md` |
| 动态顺序、富文本、高亮链接、递归悬浮 | `translations/composite-text-rules.json`；直接查询 `EntryPointId` 和 `RuleId` |
| 启动/XML/设置/宗教/ClanCard | `crash-risks.md`，再读 `crash-risks/startup-and-content.md` |
| 字体、图集、图标、缺字形、重载/OOM | `crash-risks.md`，再读 `crash-risks/runtime-and-assets.md` |
| Common/UI/Game/ElfTools 重写或逻辑敏感文本 | `crash-risks.md`，再读 `crash-risks/managed-rewrites.md` |
| 需要复现或手动输入 | 选定接口专题与 `operations/game-automation.md` |
| 曾被拒绝的历史操作数 | `text-sources/localization-safety.md` 和 `translations/localization-safety-registry.json` |

## 步骤

1. 将报告分类为：崩溃、原始键、乱码、未翻译显示文本、缺失资产、图标/字体问题、
   布局或逻辑敏感文本。
2. 对截图可见文本，直接源搜索前先查询 SQLite。DLL 操作数使用精确的 `Original`、
   `SourceFile`、`Locators`；不得使用用户审查导出。
3. 从优先级索引选择第一个安全来源。不能因没有截图就跳过已发现的显示候选。
4. 对组合文本，找到其 `EntryPointId` 和现有 `RuleId`；添加任意片段前先复用完整
   显示规则。添加条目专用规则前，识别每个引用文本、其出现次数，以及一种安全的
   统一翻译是否适用于所有调用点。先应用安全统一翻译；只有共享且仍未翻译的引用
   在已证明调用者中不能使用同一中文形式时，才添加条目规则，并记录决定及冲突
   格式。
5. 按风格指南翻译安全文本。概念链接按键查询
   `translations/concept-key-translations.json` 后选择显示词。保留结构标签，不能为了
   风格一致扩大逻辑敏感变更。
6. 只做覆盖观察到显示路径的最小来源编辑。
7. 将已变更树交给打包/安装/烟测。测试前不要更新知识；将发现保留在当前交接。

## 停止条件

- 唯一可能编辑为没有隔离回归的逻辑敏感项。
- 同一失败三次修复/测试循环后没有新证据。
- 现有条件无法解决人工视觉判断。
- 时间或任务预算结束。
