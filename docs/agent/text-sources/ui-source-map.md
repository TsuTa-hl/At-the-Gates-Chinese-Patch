# Known UI Source Map

Use this map after the SQLite catalog points to a UI family. It is a routing aid,
not a complete candidate list.

| Surface | Preferred source path |
| --- | --- |
| Main menu, load screen, top-level tooltips | UI exact `ldstr`, then runtime final-display map |
| Knowledge node/details and upgrade tooltips | XML/config names plus Common/Game display fragments or runtime rich text |
| Clan screen/cards/actions | UI layout strings, ClanTraits config, and final rich-text display rules |
| Clan list header, nested Level tooltip, and distance units | UI title-row method for headers; `ClanListEntry.BuildPanel_Contents` for `tile`/`tiles`; Common concept display only for the secondary link |
| Selected settlement/unit commands | Game static-check text, OnMap structures config, runtime display map |
| Terrain/resource lower-right tooltip | XML aliases and `English.xml` resource/terrain names |
| Help, hotkeys, dialogs | UI or ElfTools helper display strings |
| Religion choices | stable Religion config fields by ID |

When this map and the SQLite result disagree, the catalog occurrence wins.

For a visible English word with grammatical variants, first identify its exact
source-scoped display family before translating it.  Do not add a global word
rewrite just to cover a singular or plural form.  For example, the Clan List
distance suffix has two adjacent `ldstr` operands in
`ClanListEntry.BuildPanel_Contents`: `tiles` at IL offset 2120 and `tile` at
IL offset 2127.  Both must map to `格`; the patch test enforces that pair.
