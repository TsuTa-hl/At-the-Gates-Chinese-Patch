# XML、托管补丁和富文本

对 XML、UI/Common/Game/ElfTools 程序集和运行时显示映射使用精确来源证据。

## XML 和配置

- 保留稳定 ID 和 XPath/节点身份。
- 保持原始运行时令牌不变；除非来源本就如此建模，否则不要将 `[FARMER:S]` 或
  `[TIMBER]` 变成概念链接。
- 只修改 `[display|CONCEPT-KEY]` 链接的显示部分。保留键、颜色、热键、占位符和
  递归结构。

## 托管程序集

- 优先使用 `MethodToken + ILOffset + Original` 的 UI IL 重写。
- 字节或偏移回退补丁需要精确原始字节检查和定向回归。绝不以宽泛文本搜索证明偏移。
- `#US` 堆补丁不能扩展条目；必须失败，不得填充或覆盖相邻元数据。
- Common/Game/ElfTools 编辑默认只显示且范围很窄。修改生命周期、设置、概念、日期
  或行为相邻文本前阅读 `../crash-risks.md`。

## 组合

动态短语直接按 `EntryPointId` 和 `RuleId` 查询
`translations/composite-text-rules.json`。现有 Rule ID 覆盖同一最终显示边界时应
复用它。用户审查输出不是 AI 输入。已有完整模板或最终显示规则时，不得重新引入
词级 `and/from/or/a` 补丁。

## 近期精确证据

- `TRAIT_Miserable` 上下文心情提示有两条独立范围显示路径：
  `ATGUnit.RecalcMood` 提供默认心情组合，`GAME.BuildDescription_Mood` 提供氏族到
  心情的连接词。前者保留现有 `runtime-display-template` 组合规则；后者只在方法
  `0x06001731`、IL 偏移 285 本地化。任一路径均以 `SYI-ITT` 固定存档回归为必要
  证据。
