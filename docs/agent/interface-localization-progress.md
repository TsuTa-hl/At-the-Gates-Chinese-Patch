# Interface localization progress review

This review is a static source-and-entry audit. It does not use black-box
scenarios, screenshots, saves, tooltip verification flags, or reachability
observations as completion evidence.

## Generate an isolated review

From the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\Export-InterfaceLocalizationProgress.ps1
```

The command rebuilds KnownText data into a task-local `.tmp` directory before
writing three disposable outputs:

- `interface-localization-summary.csv` groups interface, surface, and trigger;
- `interface-localization-items.csv` lists every source item, stable locator,
  entry point/rule links, source state, and build synchronization state;
- `interface-localization-metadata.json` records input fingerprints, totals,
  catalog validation, and the two formulas.

Use `-KnownTextCsvPath` only for an explicitly captured private snapshot. It is
not the normal path because a source edit must rebuild the catalog first.

## Progress meanings

`VisibleLocalizationRate` is the count of visible, translatable items with a
non-empty Chinese source translation and exact source locator divided by the
visible translatable denominator. `AllKnownTrackingRate` is the count assigned
to an explicit route divided by every known item; `Unclassified` remains in its
denominator. Technical, structural, rejected, and language-neutral rows are
shown separately and are never silently treated as Chinese completion.

`BuildArtifactState` is `Current` only when the build report's localization
input SHA-256 equals the current source-map digest. A legacy or missing report
is `Unavailable`; a mismatched report is `Stale`.

## Current isolated baseline

The 2026-07-30 private snapshot produced 13,080 item rows and 16 summary rows.
It identified 2,487 visible translatable items, of which 2,466 have localized
source text and exact source locators. It explicitly classified 3,321 items;
9,759 remain `Unclassified` pending more exact route metadata. Tooltip groups
include terrain/resource (143), clan traits (337), clan list/tooltips (310),
profession (191), tile (90), knowledge/tech (85), structure/resource output
(64), and generic mouseover (41). Conditional groups include selection (702),
world/notifications (658), stockpile/resources (173), and runtime final
display (109).

The independent route ledger below is the review table. `已汉化/可翻译` is
the static source-localization rate; `全部已知` includes excluded and
unclassified rows, so it is not a completion rate. `未翻译` and `原文未变`
remain actionable rather than being counted as complete.

| 路由 | 界面类型 | 表面/条件 | 全部已知 | 可翻译 | 已汉化 | 率 | 未翻译 | 原文未变 | 排除 | 拒绝 |
| --- | --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `clan-screen` | 氏族界面与列表 | 界面 / Always | 115 | 105 | 105 | 100% | 0 | 0 | 10 | 0 |
| `clan-tooltip` | 氏族界面与列表 | 悬浮提示 / Hover | 310 | 173 | 172 | 99.42% | 0 | 0 | 137 | 1 |
| `clan-trait-config-tooltip` | 氏族特质 | 悬浮提示 / ClanState | 337 | 337 | 337 | 100% | 0 | 0 | 0 | 0 |
| `generic-mouseover-tooltip` | 通用悬浮提示 | 悬浮提示 / Hover | 41 | 23 | 23 | 100% | 0 | 0 | 18 | 0 |
| `knowledge-tech-religion` | 知识、科技与宗教 | 界面 / Always | 6 | 6 | 6 | 100% | 0 | 0 | 0 | 0 |
| `knowledge-tech-tooltip` | 知识、科技与宗教 | 悬浮提示 / Hover | 85 | 64 | 64 | 100% | 0 | 0 | 21 | 0 |
| `main-menu-help-dialog` | 主菜单、载入、帮助与对话框 | 界面 / Always | 297 | 183 | 181 | 98.91% | 0 | 2 | 114 | 0 |
| `map-terrain-resource-tooltip` | 地图地形、矿藏与资源 | 悬浮提示 / MapDiscovery | 143 | 143 | 143 | 100% | 0 | 0 | 0 | 0 |
| `profession-tooltip` | 职业与学科 | 悬浮提示 / Hover | 191 | 105 | 105 | 100% | 0 | 0 | 86 | 0 |
| `runtime-final-display` | 运行时最终显示 | 条件显示 / RuntimeComposition | 109 | 109 | 109 | 100% | 0 | 0 | 0 | 0 |
| `selection-context` | 选中对象与指令 | 条件显示 / SelectionState | 702 | 605 | 603 | 99.67% | 2 | 0 | 97 | 0 |
| `stockpile-resource-panel` | 库存与资源面板 | 条件显示 / GameState | 173 | 130 | 128 | 98.46% | 2 | 0 | 43 | 0 |
| `structure-resource-tooltip` | 建筑与资源产出 | 悬浮提示 / Hover | 64 | 14 | 12 | 85.71% | 2 | 0 | 50 | 0 |
| `tile-tooltip` | 地图格与选中信息 | 悬浮提示 / Hover | 90 | 39 | 39 | 100% | 0 | 0 | 51 | 0 |
| `world-notification-context` | 世界界面与通知 | 条件显示 / GameStateOrEvent | 658 | 451 | 439 | 97.34% | 10 | 2 | 207 | 0 |
| `Unclassified` | 尚未建立精确入口映射 | 未分类 | 9,759 | 0 | 0 | — | 11 | 25 | 5,245 | 7 |

The denominator currently contains 9,759 unclassified rows; therefore the
table is a progress baseline, not a claim that the whole game is complete.

The snapshot used for this baseline was supplied as a private CSV because the
existing source snapshot failed the legacy Composite validator with a concept-
link key mismatch. That failure is retained as a catalog validation status and
does not inflate completion.

If a fresh rebuild fails before producing a KnownText CSV, the exporter writes
`interface-localization-failure.json` with `CompletionAllowed=false` and stops;
it never substitutes an old catalog while presenting a normal completion table.

## Latest static test session (2026-07-30)

- PowerShell parsing passed for the digest helper, exporter, progress gate,
  build integration, and runtime build-report validator.
- The private-snapshot export passed with 13,080 unique item IDs and 16
  summary rows. Totals are 2,487 visible translatable, 2,466 localized,
  3,321 explicitly tracked, and 9,759 unclassified.
- The route/static gate passed without black-box scenario input. Digest
  generation was deterministic (`DigestEqual=True`) across two reads.
- A fresh source/catalog rebuild was also attempted. Its upstream KnownText
  step failed on the existing `Nodes` property error; the exporter emitted
  `interface-localization-failure.json` with `CompletionAllowed=false`, so no
  completion table was produced from that failed rebuild.
- The existing patch build report was checked read-only and is rejected because
  it predates the new localization-input fingerprint; the next patch build
  must regenerate it before a `Current` artifact state can be claimed.
- No game launch or black-box UI run was used for this static audit.
