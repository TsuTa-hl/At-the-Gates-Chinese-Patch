# 已知 UI 来源映射

在 SQLite catalog 指向某个 UI 家族后使用此映射。它是路由辅助，不是完整候选清单。

| 界面 | 优先来源路径 |
| --- | --- |
| 主菜单、加载界面、顶层提示 | UI 精确 `ldstr`，再到运行时最终显示映射 |
| 知识节点/详情和升级提示 | XML/配置名称，加 Common/Game 显示片段或运行时富文本 |
| 氏族界面/卡片/操作 | UI 布局字符串、ClanTraits 配置和最终富文本显示规则 |
| 氏族列表标题、嵌套等级提示和距离单位 | 标题用 UI 标题行方法；`tile`/`tiles` 用 `ClanListEntry.BuildPanel_Contents`；次要链接才使用 Common 概念显示 |
| 选定定居点/单位命令 | Game 静态检查文本、OnMap 建筑配置、运行时显示映射 |
| 地形/资源右下提示 | XML 别名及 `English.xml` 资源/地形名称 |
| 帮助、热键、对话框 | UI 或 ElfTools 帮助显示字符串 |
| 宗教选择 | 按 ID 的稳定 Religion 配置字段 |

本映射与 SQLite 结果冲突时，以 catalog 出现位置为准。

对于有语法变体的可见英文词，翻译前先定位其精确的来源范围显示家族。不得仅为
覆盖单复数形式就添加全局词重写。例如，氏族列表距离后缀在
`ClanListEntry.BuildPanel_Contents` 中有两个相邻 `ldstr`：IL 偏移 2120 的 `tiles`
和偏移 2127 的 `tile`。两者都必须映射为 `格`，补丁测试会强制此对。
